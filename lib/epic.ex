defmodule Bonfire.Epics.Epic do
  defstruct prev: [],
            # list of steps we've already run.
            # the remaining steps, may be modified during run.
            next: [],
            # any errors accrued along the way.
            errors: [],
            # any information accrued along the way
            assigns: %{}

  alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic
  alias Bonfire.Epics.Error

  require Untangle
  use Arrows
  require Act
  import Bonfire.Common.Extend
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Enums
  alias Bonfire.Common.Config

  @type t :: %Epic{
          prev: [Act.t()],
          next: [Act.t()],
          errors: [any],
          assigns: %{optional(atom) => any}
        }

  @doc """
  Loads an epic from the app's config
  """
  def from_config!(module, name) when is_atom(module) and is_atom(name) do
    case Application.get_application(module) do
      nil ->
        raise RuntimeError, message: "Module's otp_app not found: #{module}"

      app ->
        Config.get_ext!(app, [module, :epics, name])
        |> from_spec!()
    end
  end

  @doc """
  Loads an epic from a specification of steps
  """
  def from_spec!(acts) when is_list(acts) do
    Enum.map(acts, fn act ->
      case act do
        _ when is_atom(act) ->
          Act.new(act)

        {module, options} when is_atom(module) and is_list(options) ->
          Act.new(module, options)

        _ when is_list(act) ->
          # TODO: run a list of Acts in parallel
          from_spec!(act)

        other ->
          raise RuntimeError,
            message: "Bad `Act` specification: #{inspect(other)}"
      end
    end)
    |> Epic.new()
  end

  def assign(%Epic{} = self, name) when is_atom(name), do: self.assigns[name]

  def assign(%Epic{} = self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value)}

  def update(%Epic{} = self, name, default, fun) when is_function(fun),
    do: assign(self, name, fun.(Map.get(self.assigns, name, default)))

  def update(epic, name, default_value, fun) when is_function(fun) do
    %{epic | assigns: Map.update(epic.assigns, name, default_value, fun)}
  end

  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  def prepend(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: acts ++ self.next}

  def prepend(%Epic{} = self, act), do: %{self | next: [act | self.next]}

  def append(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: self.next ++ acts}

  def append(%Epic{} = self, act), do: %{self | next: self.next ++ [act]}

  def add_error(%Epic{} = epic, %Error{} = error),
    do: %{epic | errors: [error | epic.errors]}

  def add_error(%Epic{} = epic, act, error, source \\ nil, stacktrace \\ nil),
    do:
      add_error(epic, %Error{
        error: error,
        act: act,
        epic: epic,
        source: source,
        stacktrace: stacktrace
      })

  defmacro maybe_debug(epic, thing, label \\ "") do
    quote do
      require Untangle

      if unquote(epic).assigns.options[:debug],
        do: Untangle.warn(unquote(thing), unquote(label)),
        else: Untangle.debug(unquote(thing), unquote(label))
    end
  end

  def run(%Epic{} = epic) do
    case epic.next do
      [%Act{} = act | next_acts] ->
        # run next Act
        maybe_run_act(act, %{epic | next: next_acts})

      [%{next: parallel_acts} | next_acts] ->
        # run some async Acts in parallel
        # NOTE: should we instead run in background (and not await) and use handle_info to notify the liveview only in case there was an error? see https://hexdocs.pm/elixir/Task.html#await/2-compatibility-with-otp-behaviours

        epic =
          epic
          |> Map.put(:next, [])

        # |> Untangle.dump("epic")

        # Untangle.dump(next_acts, "run after parallel")

        parallel_acts
        # |> Untangle.dump("WIP: run in parallel")
        |> Enum.map(fn act ->
          Utils.async_task(fn -> maybe_run_act(act, epic) end)
        end)
        # long timeout to support slow operation like file uploads - TODO: configurable in the epic definition
        |> Task.await_many(1_000_000)
        # |> Untangle.dump("parallel done")
        |> Enum.reduce(fn x, acc ->
          Map.merge(x, acc, fn _key, prev, next ->
            cond do
              is_list(prev) ->
                # append errors
                Enum.uniq(prev ++ next)

              is_map(prev) ->
                # TODO: only merge what we actually need
                Enums.deep_merge(prev, next, replace_lists: true)

              next == nil ->
                prev

              true ->
                next
            end
          end)
        end)
        # |> Untangle.dump("parallel merged return")
        # continue to run acts (if any) *after* the parallel ones
        |> Map.put(:next, next_acts)
        |> run()

      [] ->
        # all Acts are done
        epic

      other ->
        Untangle.error(other, "There seems to be an error in the definition of epics")
    end
  end

  defp maybe_run_act(act, epic) do
    crash? = epic.assigns[:options][:crash]

    cond do
      not Code.ensure_loaded?(act.module) ->
        Untangle.warn(act.module, "Skipping act, module not found")
        run(epic)

      not module_enabled?(act.module) ->
        # TODO: need to check if the module is disabled for the current user
        maybe_debug(epic, act.module, "Skipping act, module disabled")
        run(epic)

      not function_exported?(act.module, :run, 2) ->
        raise RuntimeError,
          message:
            "Could not run act (module callback not found), act #{inspect(act, pretty: true, printable_limit: :infinity)}"

      crash? ->
        do_run_act(epic, act)

      true ->
        try do
          do_run_act(epic, act)
        rescue
          error ->
            # IO.puts(Exception.format_banner(:error, error, __STACKTRACE__))
            run(add_error(epic, act, error, :error, __STACKTRACE__))
        catch
          :exit, error ->
            exit(error)

          # run(add_error(epic, act, error, :exit, __STACKTRACE__))
          error ->
            # IO.puts(Exception.format_banner(:throw, error, __STACKTRACE__))
            run(add_error(epic, act, error, :throw, __STACKTRACE__))
        end
    end
  end

  defp do_run_act(epic, act) do
    maybe_debug(epic, act.module, "Running act")

    case apply(act.module, :run, [epic, act]) do
      %Epic{} = epic ->
        run(%{epic | prev: [act | epic.prev]})

      %Act{} = act ->
        run(%{epic | prev: [act | epic.prev]})

      %Error{} = error ->
        run(add_error(epic, error))

      {:ok, %Epic{} = epic} ->
        run(%{epic | prev: [act | epic.prev]})

      {:ok, %Epic{} = epic, %Act{} = act} ->
        run(%{epic | prev: [act | epic.prev]})

      {:error, %Error{} = error} ->
        run(add_error(epic, error))

      {:error, other} ->
        run(add_error(epic, act, other, :return))

      other ->
        raise RuntimeError,
          message: """
          Invalid act return: #{inspect(other)}

          Act: #{inspect(act)}
          """
    end
  end

  defmacro debug(epic, thing, label \\ "") do
    quote do
      require Untangle

      Untangle.maybe_dbg(
        unquote(thing),
        unquote(label),
        unquote(epic).assigns.options
      )
    end
  end

  def render_errors(%Epic{} = epic) do
    for(error <- epic.errors, do: render_errors(error))
    |> Enum.join("\n")
  end

  def render_errors(%Error{} = error), do: Error.message(error)
  def render_errors(_), do: nil
end

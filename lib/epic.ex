defmodule Bonfire.Epics.Epic do
  @moduledoc """
  Represents and manages an Epic, which is a sequence of Acts to be executed.

  An Epic is a struct containing lists of previous and next steps, errors, and assigns.

  This module provides functionality to create, modify, and run Epics, as well as handle errors
  and debugging.
  """

  @typedoc """
  Represents an Epic struct.

  - `:prev` - List of Acts that have already been run.
  - `:next` - List of remaining Acts to be run (may be modified during run).
  - `:errors` - List of errors (accrued during run).
  - `:assigns` - Map of assigned values (may be modified during run).
  """
  defstruct prev: [],
            next: [],
            errors: [],
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

  defmacro maybe_debug(epic, thing, label \\ "") do
    quote do
      require Untangle

      if unquote(epic).assigns.options[:debug],
        do: Untangle.info(unquote(thing), unquote(label)),
        else: Untangle.debug(unquote(thing), unquote(label))
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

  @doc """
  Loads an epic from the app's config.

  ## Parameters

  - `config_key`: The config key to load, such as a module atom (in which case it will load it from that module's app config).
  - `name`: The name atom of the epic in the config.

  ## Examples

      iex> Bonfire.Epics.Epic.from_config!(MyApp.Module, :my_epic)
      %Bonfire.Epics.Epic{...}

      iex> Bonfire.Epics.Epic.from_config!(:my_key, :my_other_epic)
      %Bonfire.Epics.Epic{...}

  """
  def from_config!(config_key, name) when is_atom(config_key) and is_atom(name) do
    case Application.get_application(config_key) do
      nil ->
        Config.get!([config_key, :epics, name])

      app ->
        Config.get_ext!(app, [config_key, :epics, name])
        |> from_spec!()
    end
  end

  @doc """
  Creates an `Epic` from a specification of steps.

  ## Parameters

  - `acts`: A list of act specifications.

  ## Examples

      iex> Bonfire.Epics.Epic.from_spec!([MyAct, {OtherAct, [option: :value]}])
      %Bonfire.Epics.Epic{...}

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

  # def assign(%Epic{} = self, name) when is_atom(name), do: self.assigns[name]

  @doc """
  Assigns a value to the Epic's assigns.

  ## Parameters

  - `self`: The Epic struct.
  - `name`: The atom key for the assign.
  - `value`: The value to assign.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{}
      iex> Bonfire.Epics.Epic.assign(epic, :foo, "bar")
      %Bonfire.Epics.Epic{assigns: %{foo: "bar"}}

  """
  def assign(%Epic{} = self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value)}

  @doc """
  Updates an assign in the Epic using a function.

  ## Parameters

  - `self`: The Epic struct.
  - `name`: The atom key for the assign.
  - `default`: The default value if the assign doesn't exist.
  - `fun`: The function to apply to the current value.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{assigns: %{count: 1}}
      iex> Bonfire.Epics.Epic.update(epic, :count, 0, &(&1 + 1))
      %Bonfire.Epics.Epic{assigns: %{count: 2}}

  """
  def update(%Epic{} = self, name, default, fun) when is_function(fun),
    do: assign(self, name, fun.(Map.get(self.assigns, name, default)))

  def update(epic, name, default_value, fun) when is_function(fun) do
    %{epic | assigns: Map.update(epic.assigns, name, default_value, fun)}
  end

  @doc """
  Creates a new Epic with the given list of next steps.

  ## Parameters

  - `next`: A list of Acts to be executed.

  ## Examples

      iex> Bonfire.Epics.Epic.new([MyAct, OtherAct])
      %Bonfire.Epics.Epic{next: [MyAct, OtherAct]}

  """
  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  @doc """
  Prepends Act(s) to the beginning of the Epic's next steps.

  ## Parameters

  - `self`: The Epic struct.
  - `acts`: A list of Acts or a single Act to prepend.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{next: [Act2]}
      iex> Bonfire.Epics.Epic.prepend(epic, [Act1])
      %Bonfire.Epics.Epic{next: [Act1, Act2]}

  """
  def prepend(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: acts ++ self.next}

  def prepend(%Epic{} = self, act), do: %{self | next: [act | self.next]}

  @doc """
  Appends Act(s) to the end of the Epic's next steps.

  ## Parameters

  - `self`: The Epic struct.
  - `acts`: A list of Acts or a single Act to append.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{next: [Act1]}
      iex> Bonfire.Epics.Epic.append(epic, [Act2])
      %Bonfire.Epics.Epic{next: [Act1, Act2]}

  """
  def append(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: self.next ++ acts}

  def append(%Epic{} = self, act), do: %{self | next: self.next ++ [act]}

  @doc """
  Runs the Epic, executing each Act in sequence (with some Acts optionally running in parallel).

  ## Parameters

  - `epic`: The Epic struct to run.

  ## Examples

      iex> epic = Bonfire.Epics.Epic.new([MyAct, OtherAct])
      iex> Bonfire.Epics.Epic.run(epic)
      %Bonfire.Epics.Epic{prev: [OtherAct, MyAct], next: [], ...}

  """
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
          # same as `Task.async/1` but supports multi-tenancy
          Utils.apply_task(:async, fn -> maybe_run_act(act, epic) end)
        end)
        # long timeout to support slow operation like file uploads - TODO: configurable in the epic definition
        |> Task.await_many(epic.assigns[:options][:timeout] || 5_000_000)
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

    module = maybe_module(act.module, epic.assigns[:options])

    # ^ check if the module is disabled (incl. for the current user if available in the options assigns)

    cond do
      is_nil(module) ->
        maybe_debug(epic, act.module, "Skipping act, module disabled")
        run(epic)

      not function_exported?(module, :run, 2) ->
        raise RuntimeError,
          message:
            "Could not run act (module callback not found), act #{inspect(act, pretty: true, printable_limit: :infinity)}"

      crash? ->
        do_run_act(epic, act, module)

      true ->
        try do
          do_run_act(epic, act, module)
        rescue
          error ->
            Untangle.error(Exception.format_banner(:error, error, __STACKTRACE__))
            run(add_error(epic, act, error, :error, __STACKTRACE__))
        catch
          :exit, error ->
            exit(error)

          # run(add_error(epic, act, error, :exit, __STACKTRACE__))
          error ->
            Untangle.error(Exception.format_banner(:throw, error, __STACKTRACE__))
            run(add_error(epic, act, error, :throw, __STACKTRACE__))
        end
    end
  end

  defp do_run_act(epic, act, module) do
    maybe_debug(epic, module, "Running act")

    case Utils.maybe_apply(module, :run, [epic, act]) do
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
        Untangle.error(other)
        run(add_error(epic, act, other, :return))

      # :not_applied ->
      #   maybe_debug(epic, module, "Could not find/run act module/function (maybe it is simply disabled), skipping...")
      #   run(%{epic | prev: [act | epic.prev]})

      other ->
        raise RuntimeError,
          message: """
          Invalid act return: #{inspect(other)}

          Act: #{inspect(act)}
          """
    end
  end

  @doc """
  Adds an error to the Epic.

  ## Parameters

  - `epic`: The Epic struct.
  - `error`: The Error struct to add.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{}
      iex> error = %Bonfire.Epics.Error{error: "Something went wrong"}
      iex> Bonfire.Epics.Epic.add_error(epic, error)
      %Bonfire.Epics.Epic{errors: [%Bonfire.Epics.Error{error: "Something went wrong"}]}

  """
  def add_error(%Epic{} = epic, %Error{} = error) do
    Untangle.error(error)
    %{epic | errors: [error | epic.errors]}
  end

  def add_error(%Epic{} = epic, act, error, source \\ nil, stacktrace \\ nil) do
    Untangle.error(error)

    add_error(epic, %Error{
      error: error,
      act: act,
      epic: epic,
      source: source,
      stacktrace: stacktrace
    })
  end

  @doc """
  Renders all errors in the Epic as a string.

  ## Parameters

  - `epic`: The Epic struct containing errors.

  ## Examples

      iex> epic = %Bonfire.Epics.Epic{errors: [%Bonfire.Epics.Error{error: "Error 1"}, %Bonfire.Epics.Error{error: "Error 2"}]}
      iex> Bonfire.Epics.Epic.render_errors(epic)
      "Error 1\\nError 2"

  """
  def render_errors(%Epic{} = epic) do
    for(error <- epic.errors, do: render_errors(error))
    |> Enum.join("\n")
  end

  def render_errors(%Error{} = error), do: Error.message(error)
  def render_errors(_), do: nil
end

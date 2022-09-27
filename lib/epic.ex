defmodule Bonfire.Epics.Epic do
  defstruct prev: [],
            # list of steps we've already run.
            # the remaining steps, may be modified during run.
            next: [],
            # any errors accrued along the way.
            errors: [],
            # any information accrued along the way
            assigns: %{}

  alias Bonfire.Epics
  alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic
  alias Bonfire.Epics.Error

  import Bonfire.Common.Extend
  require Untangle
  use Arrows
  require Act
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
    for act <- acts do
      case act do
        module when is_atom(module) ->
          Act.new(module)

        {module, options} when is_atom(module) and is_list(options) ->
          Act.new(module, options)

        other ->
          raise RuntimeError,
            message: "Bad act specification: #{inspect(other)}"
      end
    end
    |> Epic.new()
  end

  def assign(%Epic{} = self, name) when is_atom(name), do: self.assigns[name]

  def assign(%Epic{} = self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value)}

  def update(%Epic{} = self, name, default, fun),
    do: assign(self, name, fun.(Map.get(self.assigns, name, default)))

  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  def prepend(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: acts ++ self.next}

  def prepend(%Epic{} = self, act), do: %{self | next: [act | self.next]}

  def append(%Epic{} = self, acts) when is_list(acts),
    do: %{self | next: self.next ++ acts}

  def append(%Epic{} = self, act), do: %{self | next: self.next ++ [act]}

  def update(epic, key, default_value, fun) do
    %{epic | assigns: Map.update(epic.assigns, key, default_value, fun)}
  end

  def add_error(epic, %Error{} = error),
    do: %{epic | errors: [error | epic.errors]}

  def add_error(epic, act, %Error{} = error),
    do: %{epic | errors: [error | epic.errors]}

  def add_error(epic, act, error, source \\ nil, stacktrace \\ nil),
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

  def run(%Epic{} = self) do
    case self.next do
      [%Act{} = act | acts] -> run_act(act, acts, self)
      [] -> self
    end
  end

  defp run_act(act, rest, epic) do
    crash? = epic.assigns[:options][:crash]
    epic = %{epic | next: rest}

    cond do
      not Code.ensure_loaded?(act.module) ->
        Untangle.warn(act.module, "Skipping act, module not found")
        run(epic)

      not module_enabled?(act.module) ->
        maybe_debug(epic, act.module, "Skipping act, module disabled")
        run(epic)

      not function_exported?(act.module, :run, 2) ->
        raise RuntimeError,
          message:
            "Could not run act (module callback not found), act #{inspect(act, pretty: true, printable_limit: :infinity)}"

      crash? ->
        run_act(epic, act)

      true ->
        try do
          run_act(epic, act)
        rescue
          error ->
            # IO.puts(Exception.format_banner(:error, error, __STACKTRACE__))
            run(add_error(epic, error, act, :error, __STACKTRACE__))
        catch
          :exit, error ->
            exit(error)

          # run(add_error(epic, error, act, :exit, __STACKTRACE__))
          error ->
            # IO.puts(Exception.format_banner(:throw, error, __STACKTRACE__))
            run(add_error(epic, error, act, :throw, __STACKTRACE__))
        end
    end
  end

  defp run_act(epic, act) do
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
end

defmodule Bonfire.Epics.Epic do
  defstruct [
    prev:    [],  # list of steps we've already run.
    next:    [],  # the remaining steps, may be modified during run.
    errors:  [],  # any errors accrued along the way.
    assigns: %{}, # any information accrued along the way
  ]

  alias Bonfire.Epics.{Act, Epic, Error}
  alias Bonfire.Common.Extend
  require Where
  use Arrows
  require Act

  @type t :: %Epic{
    prev:   [Act.t],
    next:   [Act.t],
    errors: [any],
    assigns: %{optional(atom) => any},
  }

  def assign(%Epic{}=self, name) when is_atom(name), do: self.assigns[name]
  def assign(%Epic{}=self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value) }

  def update(%Epic{}=self, name, default, fun),
    do: assign(self, name, fun.(Map.get(self.assigns, name, default)))

  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  def prepend(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: acts ++ self.next }
  def prepend(%Epic{}=self, act), do: %{ self | next: [act | self.next] }

  def append(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: self.next ++ acts }
  def append(%Epic{}=self, act), do: %{ self | next: self.next ++ [act] }

  def add_error(epic, %Error{}=error), do: %{epic | errors: [error | epic.errors]}
  def add_error(epic, act, %Error{}=error), do: %{epic | errors: [error | epic.errors]}
  def add_error(epic, act, error, source \\ nil, stacktrace \\ nil),
    do: add_error(epic, %Error{error: error, act: act, epic: epic, source: source, stacktrace: stacktrace})

  defmacro maybe_debug(epic, thing, label \\ "") do
    quote do
      require Where
      if unquote(epic).assigns.options[:debug],
        do: Where.debug(unquote(thing), unquote(label))
    end
  end

  def run(%Epic{}=self) do
    case self.next do
      [%Act{}=act|acts] -> run_act(act, acts, self)
      [] -> self
    end
  end

  defp run_act(act, rest, epic) do
    crash? = epic.assigns.options[:crash]
    epic = %{ epic | next: rest }
    cond do
      not Code.ensure_loaded?(act.module) ->
        Where.warn(act.module, "Skipping act, module not found")
        run(epic)
      not Extend.module_enabled?(act.module) ->
        maybe_debug(epic, act.module, "Skipping act, module disabled")
        run(epic)
      not function_exported?(act.module, :run, 2) ->
        raise RuntimeError, message: "Could not run act (module callback not found), act #{inspect(act, pretty: true, printable_limit: :infinity)}"
      crash? ->
        run_act(epic, act)
      true ->
        try do
          run_act(epic, act)
        rescue error ->
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
      %Epic{}=epic                    -> run(%{ epic | prev: [act | epic.prev]})
      %Act{}=act                      -> run(%{ epic | prev: [act | epic.prev]})
      %Error{}=error                  -> run(add_error(epic, error))
      {:ok, %Epic{}=epic}             -> run(%{ epic | prev: [act | epic.prev]})
      {:ok, %Epic{}=epic, %Act{}=act} -> run(%{ epic | prev: [act | epic.prev]})
      {:error, %Error{}=error}        -> run(add_error(epic, error))
      {:error, other}                 -> run(add_error(epic, act, other, :return))
      other ->
        raise RuntimeError, message: """
        Invalid act return: #{inspect(other)}

        Act: #{inspect(act)}
        """
    end
  end

  defmacro debug(epic, thing, label \\ "") do
    quote do
      require Where
      Where.debug?(unquote(thing, unquote(label), unquote(epic.assigns.options)))
    end
  end

end

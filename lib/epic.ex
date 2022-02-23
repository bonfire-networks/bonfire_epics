defmodule Bonfire.Epics.Epic do
  defstruct [
    prev:    [],  # list of steps we've already run.
    next:    [],  # the remaining steps, may modified during run.
    errors:  [],  # any errors accrued along the way.
    assigns: %{}, # any information accrued along the way
  ]

  alias Bonfire.Epics
  alias Bonfire.Epics.{Act, Epic, Error}
  alias Bonfire.Common.Extend
  import Where
  use Arrows
  import Epics
  import Where
  @type t :: %Epic{
    prev:   [Act.t],
    next:   [Act.t],
    errors: [any],
    assigns: %{optional(atom) => any},
  }

  @doc """
  Loads an epic from the app's config
  """
  def from_config!(module, name) when is_atom(module) and is_atom(name) do
    case Application.get_application(module) do
      nil -> raise RuntimeError, message: "Module not found! #{module}"
      app ->
        Application.get_env(app, module, [])
        |> Keyword.fetch!(:epics)
        |> Keyword.fetch!(name)
        |> from_spec!()
    end
  end

  @doc """
  Loads an epic from a specification of steps
  """
  def from_spec!(acts) when is_list(acts) do
    for act <- acts do
      case act do
        module when is_atom(module) -> Act.new(module)
        {module, options} when is_atom(module) and is_list(options) -> Act.new(module, options)
        other ->
          raise RuntimeError, message: "Bad act specification: #{inspect(other)}"
      end
    end
    |> Epic.new()
  end

  def assign(%Epic{}=self, name) when is_atom(name), do: self.assigns[name]
  def assign(%Epic{}=self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value) }

  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  def prepend(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: acts ++ self.next }
  def prepend(%Epic{}=self, act), do: %{ self | next: [act | self.next] }

  def append(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: self.next ++ acts }
  def append(%Epic{}=self, act), do: %{ self | next: self.next ++ [act] }

  def update(epic, key, default_value, fun) do
    %{ epic | assigns: Map.update(epic.assigns, key, default_value, fun) }
  end

  def add_error(epic, %Error{}=error), do: %{epic | errors: [error | epic.errors]}
  def add_error(epic, act, %Error{}=error), do: %{epic | errors: [error | epic.errors]}
  def add_error(epic, act, error, source \\ nil, stacktrace \\ nil),
    do: add_error(epic, %Error{error: error, act: act, epic: epic, source: source, stacktrace: stacktrace})


  def smart(epic, act, thing, label), do: maybe_debug(epic, act, thing, label)

  def run(%Epic{}=self) do
    case self.next do
      [%Act{}=act|acts] -> run_act(act, acts, self)
      [] -> self
    end
  end

  defp run_act(act, rest, epic) do
    crash? = epic.assigns[:options][:crash]
    epic = %{ epic | next: rest }
    cond do
      not Code.ensure_loaded?(act.module) ->
        maybe_debug(epic, act.module, "Act module not found, skipping")
        run(epic)
      not Extend.module_enabled?(act.module) ->
        maybe_debug(epic, act.module, "Act module disabled, skipping")
        run(epic)
      not function_exported?(act.module, :run, 2) ->
        raise RuntimeError, message: "Could not run act (module callback not found), act #{inspect(act, pretty: true, printable_limit: :infinity)}"
      crash? ->
        really_run_act(epic, act)
      true ->
        try do
          really_run_act(epic, act)
        rescue error ->
          # IO.puts(Exception.format_banner(:error, error, __STACKTRACE__))
          run(add_error(epic, error, act, :error, __STACKTRACE__))
        catch  error ->
          # IO.puts(Exception.format_banner(:throw, error, __STACKTRACE__))
          run(add_error(epic, error, act, :throw, __STACKTRACE__))
        end
    end
  end

  defp really_run_act(epic, act) do
    maybe_debug(epic, act.module, "Running act")
    # try do
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

end

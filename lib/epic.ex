defmodule Bonfire.Epic do
  defstruct [
    prev:    [],  # list of steps we've already run.
    next:    [],  # the remaining steps, may modified during run.
    errors:  [],  # any errors accrued along the way.
    assigns: %{}, # any information accrued along the way
    return:  nil, # the ultimate value that will be returned to the user
  ]

  use Arrows
  alias Bonfire.Epic
  alias Bonfire.Epic.Act
  alias Bonfire.Common.Extend

  @type t :: %Epic{
    prev:   [Act.t],
    next:   [Act.t],
    errors: [any],
    assigns: %{optional(atom) => any},
    return: any,
  }

  def assign(%Epic{}=self, name) when is_atom(name), do: self.assigns[name]
  def assign(%Epic{}=self, name, value) when is_atom(name),
    do: %{self | assigns: Map.put(self.assigns, name, value) }

  def new(next \\ [])
  def new(next) when is_list(next), do: %Epic{next: next}

  def prepend(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: acts ++ self.next }
  def prepend(%Epic{}=self, act), do: %{ self | next: [act | self.next] }

  def append(%Epic{}=self, acts) when is_list(acts), do: %{ self | next: self.next ++ acts }
  def append(%Epic{}=self, act), do: %{ self | next: self.next ++ [act] }
    
  def add_error(epic, %Epic.Error{}=error), do: update_in(epic, :errors, &[error | &1])
  def add_error(epic, act, %Epic.Error{}=error), do: update_in(epic, :errors, &[error | &1])
  def add_error(epic, act, error, source \\ nil, stacktrace \\ nil),
    do: %Epic.Error{error: error, act: act, epic: epic, source: source, stacktrace: stacktrace}

  def run(%Epic{}=self) do
    case self.next do
      [%Epic.Act{}=act|acts] -> run_act(act, acts, self)
      [] ->
        case self.errors do
          [] -> {:ok, self}
          _  -> {:error, self}
        end
    end
  end

  defp run_act(act, rest, epic) do
    epic = %{ epic | next: rest }
    if Extend.module_enabled?(act.module) do
      if function_exported?(act.module, :run, 2) do
        try do
          case apply(act.module, :run, [epic, act]) do
            %Epic{}=epic                    -> run(update_in(epic, :prev, &[act | &1]))
            %Act{}=act                      -> run(update_in(epic, :prev, &[act | &1]))
            {:ok, %Epic{}=epic}             -> run(update_in(epic, :prev, &[act | &1]))
            {:ok, %Epic{}=epic, %Act{}=act} -> run(update_in(epic, :prev, &[act | &1]))
            {:error, %Epic.Error{}=error}   -> run(add_error(epic, error))
            {:error, other}                 -> run(add_error(epic, act, other, :return))
            {:ok, other} ->
              raise RuntimeError, message: """
              Invalid act return: #{inspect(other)}
  
              Act: #{inspect(act)}
              """
          end
        rescue error -> run(add_error(epic, error, act, :error, __STACKTRACE__))
        catch  error -> run(add_error(epic, error, act, :throw, __STACKTRACE__))
        end
      else
        raise RuntimeError, message: "Could not run act (module callback not found), act #{inspect(act)}"
      end
    else
      run(epic)
    end
  end

end


# defmodule Bonfire.Epic.Transaction do
#   @moduledoc """
#   """
# end

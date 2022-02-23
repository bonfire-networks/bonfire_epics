defmodule Bonfire.Epics.Test do

  alias Bonfire.Epics.{Epic, Error}

  defmacro assert_epic_ok(expr) do
    quote do
      case unquote(expr) do
        {:ok, value} -> value
        {:error, e} -> Bonfire.Epics.Test.debug_error(e)
      end
    end
  end

  def debug_error(%Epic{}=epic) do
    for error <- epic.errors, do: debug_error(error)
  end
  def debug_error(%Error{}=error), do: IO.puts(Error.message(error))
  def debug_error(error), do: IO.inspect(error)

end

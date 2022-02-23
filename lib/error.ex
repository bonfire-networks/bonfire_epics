defmodule Bonfire.Epics.Error do
  defexception [:error, :source, :act, :epic, :stacktrace]

  def message(self) do
    # throw is the one that will render anything, default to it.
    kind = if self.source in [:error, :exit], do: self.source, else: :throw
    banner = Exception.format_banner(kind, self.error, self.stacktrace)
    """
    #{banner}

    In act: #{inspect(self.act)}
    Assigns: #{inspect(self.epic.assigns)}
    """
  end
end

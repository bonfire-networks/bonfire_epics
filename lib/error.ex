defmodule Bonfire.Epics.Error do
  defexception [:error, :source, :act, :epic, :stacktrace]

  def message(self) do
    kind = if self.source == :error, do: :error, else: :throw
    Exception.format_banner(kind, self.error, self.stacktrace)
    ++ """

    In act: #{inspect(self.act)}
    History (most recent first): #{inspect(self.epic.prev)}
    Assigns: #{inspect(self.epic.assigns)}
    """
  end
end

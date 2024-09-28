defmodule Bonfire.Epics.Error do
  import Untangle

  alias Bonfire.Common.Errors

  defexception [:error, :source, :act, :epic, :stacktrace]

  def message(self) do
    # if Bonfire.Common.Config.env() !=:prod do
    # throw is the one that will render anything, default to it.
    kind = if self.source in [:error, :exit], do: self.source, else: :throw
    banner = Errors.format_banner(kind, self.error, self.stacktrace)

    error(self.act, banner)
    debug(Untangle.format_stacktrace(self.stacktrace), "Act stacktrace")
    debug(self.epic.assigns, "Act assigns")

    # else
    Errors.error_msg(self.error)
    # end
  end
end

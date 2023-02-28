defmodule Bonfire.Epics.Error do
  import Untangle

  defexception [:error, :source, :act, :epic, :stacktrace]

  def message(self) do
    error = Bonfire.Common.Errors.error_msg(self.error)

    # if Bonfire.Common.Config.env() !=:prod do
    # throw is the one that will render anything, default to it.
    kind = if self.source in [:error, :exit], do: self.source, else: :throw
    banner = Exception.format_banner(kind, error, self.stacktrace)

    error(self.act, banner)
    debug(self.stacktrace, "Act stacktrace")
    debug(self.epic.assigns, "Act assigns")

    # else
    error
    # end
  end
end

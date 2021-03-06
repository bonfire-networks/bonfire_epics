defmodule Bonfire.Epics.Debug do

  require Logger
  alias Bonfire.Epics.{Act, Epic}

  @level :info # TODO: configurable

  def do_maybe_debug(nil, %Act{} = act, thing, label) do
    if act.options[:debug],
      do: Logger.log(@level, "#{label} #{inspect thing}")
  end

  def do_maybe_debug(nil, %Epic{} = epic, thing, label) do
    if epic.assigns[:options][:debug],
      do: Logger.log(@level, "#{label} #{inspect thing}")
  end

  def do_maybe_debug(%Epic{} = epic, %Act{} = act, thing, label) do
    if epic.assigns[:options][:debug] || act.options[:debug],
      do: Logger.log(@level, "#{label} #{inspect thing}")
  end

end

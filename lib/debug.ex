defmodule Bonfire.Epics.Debug do

  import Where
  alias Bonfire.Epics.{Act, Epic}

  def do_maybe_debug(nil, %Act{} = act, thing, label) do
    if act.options[:debug],
      do: warn(thing, label)
  end

  def do_maybe_debug(nil, %Epic{} = epic, thing, label) do
    if epic.assigns[:options][:debug],
      do: warn(thing, label)
  end

  def do_maybe_debug(%Epic{} = epic, %Act{} = act, thing, label) do
    if epic.assigns[:options][:debug] || act.options[:debug],
      do: warn(thing, label)
  end

end

defmodule Bonfire.Epics.Debug do
  require Logger
  alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  def do_maybe_debug(epic, act, thing, label) do
    opts = opts(epic, act)

    if opts[:debug] || opts[:level],
      do: Logger.log(opts[:level] || :warn, "#{label} #{inspect(thing)}"),
      else: Logger.log(:debug, "#{label} #{inspect(thing)}")

    thing
  end

  def opts(%Epic{} = epic, %Act{} = act) do
    Map.merge(
      Map.new(epic.assigns[:options] || %{}),
      Map.new(act.options || %{})
    )
  end

  def opts(%Epic{} = epic, _) do
    epic.assigns[:options] || %{}
  end

  def opts(_, %Act{} = act) do
    act.options || %{}
  end

  def opts(_, _) do
    %{}
  end
end

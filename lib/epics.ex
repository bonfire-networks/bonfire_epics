defmodule Bonfire.Epics do

  defmacro maybe_debug(epic, act, thing, label) do
    quote do
      import Where
      Bonfire.Epics.Debug.do_maybe_debug(unquote(epic), unquote(act), unquote(thing), unquote(label))
    end
  end

  defmacro maybe_debug(act_or_epic, thing, label \\ nil) do
    quote do
      import Where
      Bonfire.Epics.Debug.do_maybe_debug(nil, unquote(act_or_epic), unquote(thing), unquote(label))
    end
  end


end

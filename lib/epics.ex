defmodule Bonfire.Epics do
  defmacro maybe_debug(epic, act, thing, label) do
    quote do
      Bonfire.Epics.Debug.do_maybe_debug(
        unquote(epic),
        unquote(act),
        unquote(thing),
        unquote(label)
      )
    end
  end

  defmacro maybe_debug(act_or_epic, thing, label \\ nil) do
    quote do
      Bonfire.Epics.Debug.do_maybe_debug(
        nil,
        unquote(act_or_epic),
        unquote(thing),
        unquote(label)
      )
    end
  end

  @doc """
  Like `debug`, but will omit fully outputting the inspectable thing
  and still print the message if only `:debug` is set
  """
  defmacro smart(epic, act, thing, label \\ "") do
    quote do
      require Untangle

      Untangle.smart(
        unquote(thing),
        unquote(label),
        Bonfire.Epics.Debug.opts(unquote(epic), unquote(act))
      )
    end
  end
end

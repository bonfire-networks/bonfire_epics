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

  @doc """
  Log some inspect output to debug if the `:debug` key is set in the act or epic options
  """
  defmacro debug(epic, act, thing, label \\ "") do
    opts = Macro.var(:opts, __MODULE__)
    quote do
      require Where
      unquote(opts) = Map.to_list(Map.merge(Map.new(unquote(epic).assigns.options), Map.new(unquote(act).options)))
      if unquote(opts)[:debug] do
        Where.debug(unquote(thing), unquote(label))
      end
    end
  end

  @doc """
  Like `debug`, but additionally checks for the `:verbose` option.

  Intended for output that could get large.
  """
  defmacro verbose(epic, act, thing, label \\ "") do
    opts = Macro.var(:opts, __MODULE__)
    quote do
      require Where
      unquote(opts) = Map.to_list(Map.merge(Map.new(unquote(epic).assigns.options), Map.new(unquote(act).options)))
      Where.debug?(unquote(thing), unquote(label), unquote(opts))
    end
  end

  @doc """
  Like `verbose`, but will omit fully outputting the inspectable thing
  and still print the message if only `:debug` is set
  """
  defmacro smart(epic, act, thing, label \\ "") do
    opts = Macro.var(:opts, __MODULE__)
    quote do
      require Where
      unquote(opts) = Map.to_list(Map.merge(Map.new(unquote(epic).assigns.options), Map.new(unquote(act).options)))
      Where.smart(unquote(thing), unquote(label), unquote(opts))
    end
  end

  # @doc """
  # Logs a warning in the same format as `debug` or `verbose`.
  # """
  # defmacro warn(thing, label \\ "") do
  #   quote do
  #     require Where
  #     Where.warn(unquote(thing), unquote(label))
  #   end
  # end

end

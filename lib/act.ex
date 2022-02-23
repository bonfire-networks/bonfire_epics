defmodule Bonfire.Epics.Act do
  @enforce_keys [:module]
  defstruct @enforce_keys ++ [options: [], meta: nil]

  alias Bonfire.Epics.{Act, Epic}

  @type t :: %Act{
    module:  module,
    options: Keyword.t,
    meta:    any,
  }

  def new(module), do: %Act{module: module}
  def new(module, options), do: %Act{module: module, options: options}
  def new(module, options, meta), do: %Act{module: module, options: options, meta: meta}

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

  @doc """
  Logs a warning in the same format as `debug` or `verbose`.
  """
  defmacro warn(thing, label \\ "") do
    quote do
      require Where
      Where.warn(unquote(thing), unquote(label))
    end
  end

  @type ret :: Epic.t | Act.t | {:ok, Epic.t} | {:ok, Act.t} | {:ok, Epic.t, Act.t} | {:error, any}

  @callback run(Epic.t, Act.t) :: ret

end

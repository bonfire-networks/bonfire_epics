defmodule Bonfire.Epics.Act do
  @enforce_keys [:module]
  defstruct @enforce_keys ++ [options: [], meta: nil]

  alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  @type t :: %Act{
          module: module,
          options: Keyword.t(),
          meta: any
        }

  def new(module), do: %Act{module: module}
  def new(module, options), do: %Act{module: module, options: options}

  def new(module, options, meta),
    do: %Act{module: module, options: options, meta: meta}

  @type ret ::
          Epic.t()
          | Act.t()
          | {:ok, Epic.t()}
          | {:ok, Act.t()}
          | {:ok, Epic.t(), Act.t()}
          | {:error, any}

  @callback run(Epic.t(), Act.t()) :: ret

  defmacro debug(act, thing, label \\ "") do
    quote do
      require Untangle

      Untangle.maybe_dbg(
        unquote(thing),
        unquote(label),
        unquote(act).assigns.options
      )
    end
  end
end

defmodule Bonfire.Epics.Act do
  @moduledoc """
  Represents an individual Act within an Epic.

  An Act is a struct containing a module to be executed, options, and metadata.

  This module provides functionality to create new Acts and define their behavior. See `Bonfire.Epics` docs for an example Act.
  """

  @enforce_keys [:module]
  defstruct @enforce_keys ++ [options: [], meta: nil]

  alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  @typedoc """
  Represents an Act struct.

  - `:module` - The module to be executed.
  - `:options` - A keyword list of options for the Act.
  - `:meta` - Any additional metadata for the Act.
  """
  @type t :: %Act{
          module: module,
          options: Keyword.t(),
          meta: any
        }

  @doc """
  Creates a new Act for the given module.

  ## Parameters

  - `module`: The module to be executed.

  ## Examples

      iex> Bonfire.Epics.Act.new(MyActModule)
      %Bonfire.Epics.Act{module: MyActModule, options: [], meta: nil}

  """
  def new(module), do: %Act{module: module}

  @doc """
  Creates a new Act for the given module, with options.

  ## Parameters

  - `module`: The module to be executed.
  - `options`: A keyword list of options for the Act.

  ## Examples

      iex> Bonfire.Epics.Act.new(MyActModule, [option1: :value1])
      %Bonfire.Epics.Act{module: MyActModule, options: [option1: :value1], meta: nil}

  """
  def new(module, options), do: %Act{module: module, options: options}

  @doc """
  Creates a new Act for the given module, with options and metadata.

  ## Parameters

  - `module`: The module to be executed.
  - `options`: A keyword list of options for the Act.
  - `meta`: Any additional metadata for the Act.

  ## Examples

      iex> Bonfire.Epics.Act.new(MyActModule, [option1: :value1], %{extra: "data"})
      %Bonfire.Epics.Act{module: MyActModule, options: [option1: :value1], meta: %{extra: "data"}}

  """
  def new(module, options, meta),
    do: %Act{module: module, options: options, meta: meta}

  @type ret ::
          Epic.t()
          | Act.t()
          | {:ok, Epic.t()}
          | {:ok, Act.t()}
          | {:ok, Epic.t(), Act.t()}
          | {:error, any}

  @doc """
  Callback for running an Act.

  This function should be implemented by modules that define Acts.

  ## Parameters

  - `epic`: The current Epic struct.
  - `act`: The current Act struct.

  ## Returns

  The return value can be one of the following:
  - `Epic.t()`
  - `Act.t()`
  - `{:ok, Epic.t()}`
  - `{:ok, Act.t()}`
  - `{:ok, Epic.t(), Act.t()}`
  - `{:error, any}`

  """
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

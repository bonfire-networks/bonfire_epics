defmodule Bonfire.Epics do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Common.Errors
  alias Bonfire.Epics.Epic

  @doc """
  Runs a series of `Bonfire.Epics.Epic` operations based on configured Acts for this module.

  ## Parameters

  - `config_key`: The config key from which to load the Epic definition, such as a module name.
  - `type`: The type of epic operation to run.
  - `options`: Options for the epic operation, including `:on` for the key in the epic assigns to return on success (default to `:result`).

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on failure.

  ## Examples

      # runs an Epic defined in config at `config :bonfire_posts, Bonfire.Posts, epics: [publish: [...]]`
      iex> Bonfire.Epics.run_epic(Bonfire.Posts, :publish, [on: :post])
      {:ok, %{}}
  """
  def run_epic(config_key, type, options \\ []) do
    env = Config.env()

    options =
      Keyword.merge([crash: env == :test, debug: env != :prod, verbose: env == :test], options)

    with %{errors: []} = epic <-
           Epic.from_config!(config_key, type)
           |> Epic.assign(:options, options)
           |> Epic.run() do
      on = options[:on] || epic.assigns[:options][:on] || :result

      debug(on, "Return result from epic assign")

      {:ok, epic.assigns[on]}
    else
      e ->
        error(e, "Error running epic")

        if options[:return_epic_on_error] do
          e
        else
          {:error, Errors.error_msg(e)}
        end
    end
  end

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

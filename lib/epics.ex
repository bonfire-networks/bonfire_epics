defmodule Bonfire.Epics do

  alias Bonfire.Epics.{Act, Epic}

  @doc """
  Loads an epic from a specification of steps
  """
  def from_spec!(acts) when is_list(acts) do
    for act <- acts do
      case act do
        module when is_atom(module) -> Act.new(module)
        {module, options} when is_atom(module) and is_list(options) -> Act.new(module, options)
        other ->
          raise RuntimeError, message: "Bad act specification: #{inspect(other)}"
      end
    end
    |> Epic.new()
  end

  def from_config!(module, name) when is_atom(module) and is_atom(name) do
    case Application.get_application(module) do
      nil -> raise RuntimeError, message: "Module not found! #{module}"
      app ->
        Application.get_env(app, module, [])
        |> Keyword.fetch!(:epics)
        |> Keyword.fetch!(name)
        |> from_spec!()
    end
  end

end

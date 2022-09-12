defmodule BonfireEpics.MixProject do
  use Mix.Project

  def project do
    [
      app: :bonfire_epics,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:untangle, "~> 0.1"},
      {:arrows,
       git: "https://github.com/bonfire-networks/arrows", branch: "main"},
      {:bonfire_common,
       git: "https://github.com/bonfire-networks/bonfire_common",
       branch: "main",
       optional: true}
    ]
  end
end

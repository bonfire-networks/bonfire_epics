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
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:pointers, git: "https://github.com/bonfire-networks/pointers", branch: "main", override: true},
      {:bonfire_common, git: "https://github.com/bonfire-networks/bonfire_common", branch: "main"},
      {:bonfire_repo, git: "https://github.com/bonfire-networks/bonfire_repo", branch: "main", optional: true},
    ]
  end
end

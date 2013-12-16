defmodule Prairie.Mixfile do
  use Mix.Project

  def project do
    [ app: :prairie,
      version: "0.0.1",
      elixir: "~> 0.10.1-dev or ~> 0.11.0 or ~> 0.12.0",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:socket] ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [ { :datastructures, github: "meh/elixir-datastructures" },
      { :socket, github: "meh/elixir-socket" } ]
  end
end

defmodule Gopher do
  def server do
    { "localhost", 8080 }
  end

  def list do
    [{ :file, "I like trains", "/trains" }]
  end

  def list(dir) do
    []
  end

  def fetch("/trains") do
    { :file, "I like trains, fo real." }
  end

  def fetch(_) do
    IO.puts "wat"

    ""
  end
end

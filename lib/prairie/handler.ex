defmodule Prairie.Handler do alias Prairie.Connection
  @doc false
  def handle(socket, what) do
    socket.packet(:line)

    case String.rstrip(socket.recv!) do
      line when line == "" or line == "\t$" or line == "/" ->
        what.list |> normalize(what)

      << type :: utf8, rest :: binary >> when type == ?1 ->
        what.list(rest) |> normalize(what)

      << type :: utf8, rest :: binary >> when type in ?0 .. ?9 or type in [?+, ?T, ?g, ?I] ->
        what.fetch(rest, type_for(type))

      resource ->
        if resource |> String.ends_with?("/") do
          what.list(resource |> String.rstrip(?/)) |> normalize(what)
        else
          what.fetch(resource)
        end
    end |> respond(socket)

    socket.shutdown
    socket.close
  end

  defp respond(response, socket) when is_list(response) do
    Enum.each response, fn { type, title, selector, { host, port } } ->
      socket.send! [type_for(type),
        title,                 ?\t,
        selector,              ?\t,
        host,                  ?\t,
        integer_to_list(port), ?\r, ?\n ]
    end

    socket.send! ".\r\n"
  end

  defp respond({ :file, path }, socket) do
    if File.exists?(path) do
      Enum.each File.stream!(path), fn
        "." <> rest ->
          socket.send! ["..", rest]

        line ->
          socket.send! line
      end
    else
      socket.send!(path |> String.replace("\n.", "\n.."))
    end

    socket.send! "\r\n.\r\n"
  end

  defp respond({ type, path }, socket) when type in [:binary, :image] do
    if File.exists?(path) do
      :file.sendfile(path, socket.to_port)
    else
      socket.send!(path)
    end
  end

  defp normalize(list, what) do
    Enum.map list, fn
      { _type, _title, _selector, { _host, _port } } = listing ->
        listing

      { type, title, selector } ->
        { type, title, selector, what.server }
    end
  end

  @types [ { ?0, :file },
           { ?1, :directory },
           { ?2, :cso },
           { ?3, :error },
           { ?4, :binhex },
           { ?5, :dos },
           { ?6, :uuenc },
           { ?7, :index },
           { ?8, :telnet },
           { ?9, :binary },
           { ?+, :server },
           { ?T, :tn3270 },
           { ?g, :gif },
           { ?I, :image },
           { ?i, :information },
           { ?s, :audio },
           { ?h, :html } ]

  Enum.each @types, fn { code, name } ->
    def type_for(unquote(code)), do: unquote(name)
    def type_for(unquote(name)), do: unquote(code)
  end
end

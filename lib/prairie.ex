defmodule Prairie do
  def open(what, options // []) do
    Process.spawn __MODULE__, :monitor, [what, options]
  end

  @doc false
  def monitor(what, options) do
    Process.flag(:trap_exit, true)

    port      = Keyword.get(options, :port, 70)
    debug     = Keyword.get(options, :debug, false)
    backlog   = Keyword.get(options, :backlog, 128)
    acceptors = Keyword.get(options, :acceptors, 5)

    server = Socket.TCP.listen!(port, [backlog: backlog])

    Enum.each 0 .. acceptors, fn _ ->
      Process.spawn_link __MODULE__, :acceptor, [Process.self, server, what]
    end

    monitor(debug)
  end

  defp monitor(debug) do
    receive do
      { :connected, _socket, pid } ->
        Process.link(pid)

      { :EXIT, _pid, :normal } ->
        nil

      { :EXIT, pid, reason } ->
        if debug do
          IO.inspect reason
        end
    end

    monitor(debug)
  end

  @doc false
  def acceptor(monitor, socket, what) do
    client  = socket.accept!(automatic: false)
    process = Process.spawn __MODULE__, :handle, [client, what]

    client.process(process)
    monitor <- { :connected, client, process }

    acceptor(monitor, socket, what)
  end

  @doc false
  def handle(socket, what) do
    socket.packet(:line)

    case String.rstrip(socket.recv!) do
      line when line == "" or line == "\t$" or line == "/" ->
        what.list([]) |> normalize(what)

      << type :: utf8, rest :: binary >> when type == ?1 ->
        if rest |> String.contains?("\t") do
          [resource, extra] = rest |> String.split("\t")
        else
          resource = rest
          extra    = nil
        end

        what.list(resource, extra: extra) |> normalize(what)

      << type :: utf8, rest :: binary >> when type in ?0 .. ?9 or type in [?+, ?T, ?g, ?I] ->
        if rest |> String.contains?("\t") do
          [resource, extra] = rest |> String.split("\t")
        else
          resource = rest
          extra    = nil
        end

        what.fetch(rest, type: type_for(type), extra: extra)

      resource ->
        if resource |> String.contains?("\t") do
          [resource, extra] = resource |> String.split("\t")
        else
          extra = nil
        end

        if resource |> String.ends_with?("/") do
          resource = resource |> String.rstrip(?/)

          what.list(resource, extra: extra) |> normalize(what)
        else
          what.fetch(resource, extra: extra)
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

  defp respond({ type, path }, socket) when type in [:binary, :image, :gif, :audio] do
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

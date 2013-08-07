defmodule Prairie do
  def open(what, options // []) do
    Process.spawn __MODULE__, :monitor, [what, options]
  end

  @doc false
  def monitor(what, options) do
    Process.flag(:trap_exit, true)

    options = Keyword.put_new(options, :host, [])
    options = Keyword.put_new(options, :port, 70)

    port      = Keyword.get(options, :port)
    debug     = Keyword.get(options, :debug, false)
    backlog   = Keyword.get(options, :backlog, 128)
    acceptors = Keyword.get(options, :acceptors, 5)

    server = Socket.TCP.listen!(port, [backlog: backlog])

    Enum.each 0 .. acceptors, fn _ ->
      Process.spawn_link __MODULE__, :acceptor, [Process.self, server, what, options]
    end

    monitor(debug)
  end

  defp monitor(debug) do
    receive do
      { :connected, _socket, pid } ->
        Process.link(pid)

      { :EXIT, _pid, :normal } ->
        nil

      { :EXIT, _pid, reason } ->
        if debug do
          IO.inspect reason
        end
    end

    monitor(debug)
  end

  @doc false
  def acceptor(monitor, socket, what, options) do
    client  = socket.accept!(automatic: false)
    process = Process.spawn __MODULE__, :handle, [client, what, options]

    client.process(process)
    monitor <- { :connected, client, process }

    acceptor(monitor, socket, what, options)
  end

  @doc false
  def handle(socket, what, options) when is_atom(what) do
    handle(socket, &what.handle/2, options)
  end

  def handle(socket, what, options) do
    socket.packet(:line)

    case socket.recv! |> String.rstrip |> String.split("\t") |> Enum.first do
      << code :: utf8, rest :: binary >> when code in ?0 .. ?Z ->
        type     = type_for(code)
        selector = rest

      "" ->
        selector = nil
        type     = nil

      line ->
        selector = line
        type     = nil
    end

    what.(selector, type) |> respond(socket, options)

    socket.shutdown
    socket.close
  end

  defp respond([], socket, _) do
    socket.send! ".\r\n"
  end

  defp respond(response, socket, options) when is_list(response) do
    Enum.each normalize(response, options), fn { type, title, selector, { host, port } } ->
      socket.send! [type_for(type),
        title,                 ?\t,
        selector,              ?\t,
        host,                  ?\t,
        integer_to_list(port), ?\r, ?\n]
    end

    socket.send! ".\r\n"
  end

  defp respond({ :file, path }, socket, _) do
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

  defp respond({ type, path }, socket, _) when type in [:binary, :image, :gif, :audio] do
    if File.exists?(path) do
      :file.sendfile(path, socket.to_port)
    else
      socket.send!(path)
    end
  end

  defp normalize(list, options) when is_list(list) do
    Enum.map list, &normalize(&1, options)
  end

  defp normalize({ _type, _title, _selector, { _host, _port } } = desc, _) do
    desc
  end

  defp normalize({ type, title, selector }, options) do
    { type, title, selector, { options[:host][:domain] || "localhost",
                               options[:host][:port] || options[:port] } }
  end

  defp normalize(information, _) when is_binary(information) do
    { :information, information, "", { "error.host", 1 } }
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
           { ?h, :html },
           { ?:, :picture },
           { ?;, :movie },
           { ?<, :sound } ]

  Enum.each @types, fn { code, name } ->
    def type_for(unquote(code)), do: unquote(name)
    def type_for(unquote(name)), do: unquote(code)
  end
end

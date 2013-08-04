defmodule Prairie do
  defrecord Listener, monitor: nil, debug: false, socket: nil, port: nil, acceptors: 1, backlog: 128, chunk_size: 4096 do
    def to_options(Listener[backlog: backlog]) do
      [backlog: backlog, automatic: false]
    end
  end

  defrecord Connection, listener: nil, socket: nil

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

    acceptor(Socket.TCP.listen!(port, [backlog: backlog]), what)
  end

  @doc false
  def acceptor(socket, what) do
    client = socket.accept!(automatic: false)
    client.process(Process.spawn Prairie.Handler, :handle, [client, what])

    acceptor(socket, what)
  end
end

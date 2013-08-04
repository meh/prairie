defmodule Wizardchan do
  defmodule HTTP do
    defrecord Response, code: nil, headers: nil, body: nil

    def get(uri, headers // []) do
      case :httpc.request(to_binary(uri) |> binary_to_list) do
        { :ok, { code, headers, body } } ->
          { :ok, Response[code: code, headers: headers(headers), body: body(body)] }

        { :error, _ } = error ->
          error
      end
    end

    def get!(uri, headers // []) do
      case get(uri, headers) do
        { :ok, response } ->
          response

        { :error, reason } ->
          raise RuntimeError, message: reason
      end
    end

    defp headers(headers) do
      Enum.map headers, fn { name, value } ->
        { list_to_binary(name), list_to_binary(value) }
      end
    end

    defp body(body) do
      list_to_binary(body)
    end
  end

  def start(options // []) do
    :application.start(:inets)

    Prairie.open(__MODULE__, options)
  end

  def server do
    { "localhost", 70 }
  end

  @host "http://wizardchan.org"
  @boards [
    { :wiz,  "General" },
    { :v9k,  "Virgin9000" },
    { :hob,  "Hobbies" },
    { :meta, "Meta" },
    { :b,    "Random" } ]

  def list do
    Enum.map @boards, fn { name, description } ->
      { :directory, "#{description} - /#{name}", "1/#{name}" }
    end
  end

  Enum.each @boards, fn { name, _ } ->
    def :list, quote(do: ["/" <> unquote(to_binary(name))]), [], do: (quote do
      catalog_for(unquote(name)) |> Enum.map fn [path, summary] ->
        [_, id] = Regex.run(%r/(\d+).html/, path)

        { :directory, "#{unquote(name)}/#{id}", "1/#{unquote(name)}/#{id}" }
      end
    end)

    def :list, quote(do: ["/" <> unquote(to_binary(name)) <> "/" <> id]), [], do: (quote do
      thread_for(unquote(name), id) |> Enum.map(fn { post_id, { img, _ } } ->
        pages = [{ :file, "/#{unquote(name)}/#{id}/#{post_id}", "0/#{unquote(name)}/#{id}/#{post_id}" }]

        if img do
          pages = [{ :image, "/#{unquote(name)}/#{id}/#{post_id}", "I/#{unquote(name)}/#{id}/#{post_id}" } | pages]
        end

        pages
      end) |> List.flatten
    end)
  end

  def fetch(resource, :file) do
    [_, board, thread_id, post_id] = String.split(resource, "/")

    { _, body } = thread_for(board, thread_id)[post_id]

    { :file, unescape(body) }
  end

  def fetch(resource, :image) do
    [_, board, thread_id, post_id] = String.split(resource, "/")

    { image, _ } = thread_for(board, thread_id)[post_id]

    { :image, HTTP.get!("#{@host}/#{board}/src/#{image}").body }
  end

  defp catalog_for(board) do
    catalog = HTTP.get!("#{@host}/#{board}/catalog.html")
    threads = %r{<div class="thread"><a href="(.*?)">.*?</a>.*?</strong><br/>(.*?)</span>}
      |> Regex.scan(catalog.body)
  end

  defp thread_for(board, thread_id) do
    thread = HTTP.get!("#{@host}/#{board}/res/#{thread_id}.html")

    posts = %r{<p class="intro" id="(\d+)">.*?(?:<a href=".*?/src/(.*?)")?<div class="body">(.*?)</div>}
      |> Regex.scan(thread.body) |> Enum.reduce(HashDict.new, fn [id, img, body], dict ->
        if img == "" do
          Dict.put(dict, id, { nil, body })
        else
          [_, img] = Regex.run(%r/(\d+).\w+$/, img)

          Dict.put(dict, id, { img, body })
        end
      end)

    [_, img] = Regex.run(%r{<div id="thread_.*?".*?<a href=".*?/src/(.*?)"}, thread.body)
    posts    = Dict.update(posts, thread_id, fn { _, body } -> { img, body } end)

    Enum.to_list(posts) |> Enum.sort(fn { a, _ }, { b, _ } ->
        binary_to_integer(a) < binary_to_integer(b)
    end)
  end

  defp unescape(body) do
    body |> String.replace("<br/><br/>", "\r\n\r\n\r\n")
  end
end

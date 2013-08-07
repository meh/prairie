defmodule Wizardchan do
  defmodule HTTP do
    defrecord Response, code: nil, headers: nil, body: nil

    def get(uri, headers // []) do
      case :httpc.request(to_binary(uri) |> binary_to_list) do
        { :ok, { code, headers, body } } ->
          headers = headers(headers)
          body    = body(body, headers)

          { :ok, Response[code: code, headers: headers, body: body] }

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

    defp body(body, headers) do
      case headers["content-type"] do
        "text/html" <> _ ->
          String.from_char_list!(body)

        _ ->
          list_to_binary(body)
      end
    end
  end

  def start(options // []) do
    :application.start(:inets)

    Prairie.open(__MODULE__, options)
  end

  @host "http://wizardchan.org"
  @boards [
    { :wiz,  "General" },
    { :v9k,  "Virgin9000" },
    { :hob,  "Hobbies" },
    { :meta, "Meta" },
    { :b,    "Random" } ]

  def handle(selector, _) when selector == "/" or selector == nil do
    Enum.map @boards, fn { name, description } ->
      { :directory, "#{description} - /#{name}", "1/#{name}" }
    end
  end

  Enum.each @boards, fn { name, _ } ->
    def :handle, quote(do: ["/" <> unquote(to_binary(name)), :directory]), [], do: (quote do
      catalog_for(unquote(name)) |> Enum.map(fn { path, summary } ->
        [_, id] = Regex.run(%r/(\d+).html/, path)

        [{ :directory, "#{id}", "1/#{unquote(name)}/#{id}" }, "", format(summary), ""]
      end) |> List.flatten
    end)

    def :handle, quote(do: ["/" <> unquote(to_binary(name)) <> "/" <> id, :directory]), [], do: (quote do
      thread_for(unquote(name), id) |> Enum.map(fn { post_id, { img, body } } ->
        header = if img do
          { :image, "#{post_id}", "I/#{unquote(name)}/#{id}/#{post_id}" }
        else
          { :file, "#{post_id}", "0/#{unquote(name)}/#{id}/#{post_id}" }
        end

        [header, "", format(body, unquote(name), id), ""]
      end) |> List.flatten
    end)
  end

  def handle(resource, :file) do
    [_, board, thread_id, post_id] = String.split(resource, "/")

    { _, body } = thread_for(board, thread_id)[post_id]

    { :file, unescape(body) }
  end

  def handle(resource, :image) do
    [_, board, thread_id, post_id] = String.split(resource, "/")

    { image, _ } = thread_for(board, thread_id)[post_id]

    { :image, HTTP.get!("#{@host}/#{board}/src/#{image}").body }
  end

  defp catalog_for(board) do
    catalog = HTTP.get!("#{@host}/#{board}/catalog.html")

    %r{<div class="thread"><a href="(.*?)">.*?</a>.*?</strong><br/>(.*?)</span>}
      |> Regex.scan(catalog.body) |> Enum.map(fn [_, path, summary] ->
        { path, summary }
      end)
  end

  defp thread_for(board, thread_id) do
    thread = HTTP.get!("#{@host}/#{board}/res/#{thread_id}.html")

    posts = %r{<p class="intro" id="(\d+)">.*?(?:<a href=".*?/src/(.*?)")?<div class="body">(.*?)</div>}
      |> Regex.scan(thread.body) |> Enum.reduce(HashDict.new, fn [_, id, img, body], dict ->
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
    body = body
      |> String.replace(%B{<br/>}, "\r\n")
      |> String.replace(%B{&gt;}, ">")
      |> String.replace(%B{&lt;}, ">")
      |> String.replace(%B{&ndash;}, "–")
      |> String.replace(%B{&hellip;}, "…")
      |> String.replace(%B{<strong>}, "*")
      |> String.replace(%B{</strong>}, "*")
      |> String.replace(%B{<em>}, "_")
      |> String.replace(%B{</em>}, "_")
      |> String.replace(%r{<span class="quote">(.*?)</span>}ms, "\\1")
      |> String.replace(%r{<span class="spoiler">(.*?)</span>}ms, "{ \\1 }")
      |> String.replace(%r{<a .*?>(.*?)</a>}ms, "\\1")
  end

  defp format(content) do
    unescape(content) |> String.split(%r/\r?\n/) |> Enum.map(&split(&1))
      |> List.flatten
  end

  defp format(content, board // nil, thread_id // nil) do
    unescape(content) |> String.split(%r/\r?\n/) |> Enum.map(fn
      ">>" <> post_id ->
        { :file, ">>#{post_id}", "0/#{board}/#{thread_id}/#{post_id}" }

      line ->
        split(line)
    end) |> List.flatten
  end

  defp split(line) do
    line = line |> String.replace(%r/\s+/, " ")

    if line =~ %r/\s/ do
      split_words(line, 58)
    else
     split_every(line, 58)
    end
  end

  defp split_every(nil, _), do: []
  defp split_every("", _),  do: [""]

  defp split_every(string, length) do
    [ String.slice(string, 0, length) |
      String.slice(string, length, String.length(string) - length) |> split_every(length) ]
  end

  def split_words(nil, _), do: []
  def split_words("", _), do: [""]

  def split_words(string, length) do
    string      = string |> String.replace(%r/^\s*/, "")
    line        = String.slice(string, 0, length) |> String.replace(%r/\s*(\w+)?$/, "")
    line_length = String.length(line)

    if line_length == 0 do
      [string]
    else
      [line | split_words(String.slice(string, line_length, String.length(string) - line_length), length)]
    end
  end
end

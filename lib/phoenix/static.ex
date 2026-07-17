defmodule Phoenix.Static do
  @moduledoc false

  # Minimal static file server for AtomVM / gen_tcp dispatch.
  # Reads packed priv via `:atomvm.read_priv/2`.

  @mimes %{
    ".css" => "text/css; charset=utf-8",
    ".gif" => "image/gif",
    ".html" => "text/html; charset=utf-8",
    ".ico" => "image/x-icon",
    ".js" => "application/javascript; charset=utf-8",
    ".json" => "application/json",
    ".png" => "image/png",
    ".svg" => "image/svg+xml",
    ".txt" => "text/plain; charset=utf-8",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2"
  }

  @doc """
  Serves a file from the app's packed `priv/static`.

  Options:
    * `:otp_app` - application atom (required for AtomVM `read_priv`)
    * `:only` - path prefixes allowed under `priv/static`
  """
  def try_serve(conn, opts \\ [])

  def try_serve(%Plug.Conn{method: method, request_path: path} = conn, opts)
      when method in ["GET", "HEAD"] do
    only = Keyword.get(opts, :only, ~w(assets fonts images favicon.ico robots.txt))
    otp_app = Keyword.get(opts, :otp_app)

    relative = normalize_path(path)

    if is_atom(otp_app) and relative != "" and allowed?(relative, only) do
      case read_priv_static(otp_app, relative) do
        {:ok, body} ->
          conn =
            conn
            |> Plug.Conn.put_resp_header("content-type", content_type(relative))
            |> Plug.Conn.put_resp_header("cache-control", "public, max-age=0")
            |> Plug.Conn.send_resp(200, if(method == "HEAD", do: "", else: body))

          {:ok, conn}

        :error ->
          :miss
      end
    else
      :miss
    end
  end

  def try_serve(_conn, _opts), do: :miss

  defp read_priv_static(otp_app, relative) do
    priv_rel = "static/" <> relative

    try do
      body = :atomvm.read_priv(otp_app, priv_rel)
      if is_binary(body), do: {:ok, body}, else: :error
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp normalize_path(<<"/", rest::binary>>), do: normalize_path(rest)
  defp normalize_path(path) when is_binary(path), do: path

  defp allowed?(relative, only) do
    Enum.any?(only, fn prefix ->
      relative == prefix or Phoenix.Binary.starts_with?(relative, prefix <> "/")
    end)
  end

  defp content_type(path) do
    case :binary.split(path, ".", [:global]) do
      [_] ->
        "application/octet-stream"

      parts ->
        ext = "." <> Phoenix.Binary.downcase_ascii(List.last(parts))
        Map.get(@mimes, ext, "application/octet-stream")
    end
  end
end

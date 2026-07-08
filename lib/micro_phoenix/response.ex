defmodule MicroPhoenix.Response do
  alias MicroPhoenix.Conn

  def build(%Conn{halted: true} = conn) do
    conn
    |> flash_headers()
    |> then(fn conn ->
      http_response(conn.status, conn.resp_content_type, conn.resp_body || "", conn.resp_headers)
    end)
  end

  def build({:ok, status, content_type, body}) do
    http_response(status, content_type, body, [])
  end

  def build({:error, 404}) do
    http_response(404, "text/plain", "404 Not Found", [])
  end

  def build({:error, 405}) do
    http_response(405, "text/plain", "405 Method Not Allowed", [])
  end

  def build(_other), do: build({:error, 404})

  defp flash_headers(%Conn{flash: flash} = conn) when map_size(flash) == 0, do: conn

  defp flash_headers(%Conn{flash: flash} = conn) do
    cookie =
      flash
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(v)}" end)
      |> Enum.join("&")

    headers = [{"set-cookie", "_micro_flash=#{cookie}; Path=/"} | conn.resp_headers]
    %{conn | resp_headers: headers}
  end

  defp http_response(status, content_type, body, headers) do
    status_line = status_line(status)
    byte_size = byte_size(body)

    header_lines =
      [
        "Content-Type: #{content_type}; charset=utf-8",
        "Content-Length: #{byte_size}",
        "Connection: close"
      ] ++ Enum.map(headers, fn {k, v} -> "#{title_case(k)}: #{v}" end)

    "#{status_line}\r\n" <> Enum.join(header_lines, "\r\n") <> "\r\n\r\n" <> body
  end

  defp title_case("location"), do: "Location"
  defp title_case("set-cookie"), do: "Set-Cookie"
  defp title_case(key), do: String.capitalize(key)

  defp status_line(200), do: "HTTP/1.1 200 OK"
  defp status_line(302), do: "HTTP/1.1 302 Found"
  defp status_line(404), do: "HTTP/1.1 404 Not Found"
  defp status_line(405), do: "HTTP/1.1 405 Method Not Allowed"
  defp status_line(code), do: "HTTP/1.1 #{code}"
end

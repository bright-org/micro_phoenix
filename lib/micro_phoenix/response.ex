defmodule MicroPhoenix.Response do
  def build({:ok, status, content_type, body}) do
    http_response(status, content_type, body)
  end

  def build({:error, status}) do
    http_response(status, "text/plain", error_body(status))
  end

  defp http_response(status, content_type, body) do
    status_line = status_line(status)
    byte_size = byte_size(body)

    "#{status_line}\r\n" <>
      "Content-Type: #{content_type}; charset=utf-8\r\n" <>
      "Content-Length: #{byte_size}\r\n" <>
      "Connection: close\r\n" <>
      "\r\n" <>
      body
  end

  defp status_line(200), do: "HTTP/1.1 200 OK"
  defp status_line(404), do: "HTTP/1.1 404 Not Found"
  defp status_line(405), do: "HTTP/1.1 405 Method Not Allowed"
  defp status_line(code), do: "HTTP/1.1 #{code}"

  defp error_body(404), do: "404 Not Found"
  defp error_body(405), do: "405 Method Not Allowed"
  defp error_body(status), do: "HTTP Error #{status}"
end

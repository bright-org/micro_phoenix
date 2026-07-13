defmodule MicroPhoenix.Response do
  def build({:ok, status, content_type, body}) do
    http_response(status, content_type, body)
  end

  def build({:error, 404}) do
    http_response(404, "text/plain", "404 Not Found")
  end

  def build({:error, 405}) do
    http_response(405, "text/plain", "405 Method Not Allowed")
  end

  defp http_response(status, content_type, body) do
    status_line = status_line(status)
    content_length = :erlang.integer_to_binary(byte_size(body))

    status_line <> "\r\n" <>
      "Content-Type: " <> content_type <> "; charset=utf-8\r\n" <>
      "Content-Length: " <> content_length <> "\r\n" <>
      "Connection: close\r\n" <>
      "\r\n" <>
      body
  end

  defp status_line(200), do: "HTTP/1.1 200 OK"
  defp status_line(404), do: "HTTP/1.1 404 Not Found"
  defp status_line(405), do: "HTTP/1.1 405 Method Not Allowed"
  defp status_line(code), do: "HTTP/1.1 " <> :erlang.integer_to_binary(code)
end

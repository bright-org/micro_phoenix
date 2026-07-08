defmodule MicroPhoenix.Static do
  @mimes %{
    ".css" => "text/css",
    ".gif" => "image/gif",
    ".html" => "text/html",
    ".ico" => "image/x-icon",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".js" => "application/javascript",
    ".json" => "application/json",
    ".png" => "image/png",
    ".svg" => "image/svg+xml",
    ".txt" => "text/plain",
    ".xml" => "application/xml"
  }

  def serve(path) when is_binary(path) do
    relative = normalize_path(path)

    case read_file(relative) do
      {:ok, body} -> {:ok, content_type(relative), body}
      :error -> :not_found
    end
  end

  def get_error_page(404), do: {:error, 404}
  def get_error_page(405), do: {:error, 405}
  def get_error_page(status), do: {:error, status}

  defp normalize_path("/"), do: "index.html"
  defp normalize_path(path), do: String.trim_leading(path, "/")

  defp read_file(relative) do
    root = Application.get_env(:micro_phoenix, :static_root, "priv/static")
    full = Path.join(root, relative)

    case File.read(full) do
      {:ok, body} -> {:ok, body}
      {:error, _} -> :error
    end
  end

  defp content_type(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> then(&Map.get(@mimes, &1, "application/octet-stream"))
  end
end

defmodule AtomvmHttpServerWeb.Controller do
  @moduledoc false

  @index_html """
  <!DOCTYPE html>
  <html lang="ja">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AtomVM HTTP Server</title>
    <style>
      body { font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; }
      h1 { color: #333; }
      .badge { display: inline-block; background: #6c4f9e; color: white;
               padding: 4px 10px; border-radius: 4px; font-size: 0.85em; }
      pre { background: #f4f4f4; padding: 12px; border-radius: 4px; }
    </style>
  </head>
  <body>
    <h1>AtomVM HTTP Server <span class="badge">Elixir</span></h1>
    <p>AtomVM上で動くElixir製HTTPサーバーのデモページです。</p>
    <h2>REST API テスト</h2>
    <button onclick="fetchStatus()">GET /api/status</button>
    <pre id="result">ボタンを押してAPIを呼び出す...</pre>
    <script>
      async function fetchStatus() {
        const el = document.getElementById('result');
        try {
          const res = await fetch('/api/status');
          const data = await res.json();
          el.textContent = JSON.stringify(data, null, 2);
        } catch (e) {
          el.textContent = 'Error: ' + e.message;
        }
      }
    </script>
  </body>
  </html>
  """

  @index2_html """
  <!DOCTYPE html>
  <html lang="ja">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AtomVM HTTP Server</title>
    <style>
      body { font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; }
      h1 { color: #333; }
      .badge { display: inline-block; background: #6c4f9e; color: white;
               padding: 4px 10px; border-radius: 4px; font-size: 0.85em; }
      pre { background: #f4f4f4; padding: 12px; border-radius: 4px; }
    </style>
  </head>
  <body>
    <h1>AtomVM HTTP Server <span class="badge">Elixir</span></h1>
    <h2>Items</h2>
    <ul>
      <%= @items %>
    </ul>
  </body>
  </html>
  """

  def index(conn), do: render(conn, :index)
  def index2(conn) do
    items = AtomvmHttpServer.Items.list_items() |> Enum.map(fn item -> "<li>#{item.name}</li>" end)
    render(conn, :index2, %{items: items})
  end

  def render(_conn, template, assigns \\ %{}) do
    case template do
      :index -> {:ok, 200, "text/html", render_template(@index_html, assigns)}
      :index2 -> {:ok, 200, "text/html", render_template(@index2_html, assigns)}
      _ -> {:error, 404}
    end
  end

  defp render_template(template, assigns) do
    Regex.replace(~r/<%=\s*@([a-zA-Z0-9_]+)\s*%>/, template, fn _, var_name ->
      atom_key =
        try do
          :erlang.binary_to_existing_atom(var_name, :utf8)
        rescue
          ArgumentError -> nil
        end

      value =
        cond do
          atom_key != nil and Map.has_key?(assigns, atom_key) -> Map.get(assigns, atom_key)
          Map.has_key?(assigns, var_name) -> Map.get(assigns, var_name)
          true -> nil
        end

      case value do
        nil -> ""
        v when is_list(v) -> Enum.join(v, "")
        v when is_binary(v) -> v
        v -> to_string(v)
      end
    end)
  end

end

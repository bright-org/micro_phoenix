defmodule AtomvmHttpServer.Static do
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

  def get("/"), do: {:ok, "text/html", @index_html}
  def get("/index.html"), do: {:ok, "text/html", @index_html}
  def get(_), do: {:error, :not_found}
end

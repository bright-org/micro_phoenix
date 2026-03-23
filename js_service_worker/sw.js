// AtomVM HTTP Server — Service Worker (Browser Edition)
// Elixir版の5モジュールを1ファイル内のクラス/オブジェクトとして再現

// --- Request (request.ex 対応) ---
const RequestParser = {
  parse(fetchRequest) {
    const url = new URL(fetchRequest.url);
    return {
      method: fetchRequest.method.toLowerCase(),
      path: url.pathname,
    };
  },
};

// --- Static (static.ex 対応) ---
const Static = {
  indexHtml: `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AtomVM HTTP Server — Service Worker Edition</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: sans-serif; background: #0f1117; color: #e0e0e0; min-height: 100vh; padding: 40px 20px; }
    .container { max-width: 640px; margin: 0 auto; }

    .arch-diagram {
      background: #1a1d27; border: 1px solid #2e3248; border-radius: 10px;
      padding: 24px; margin-bottom: 28px; text-align: center;
    }
    .arch-diagram h2 { font-size: 0.8em; color: #7a7f9a; letter-spacing: 0.1em; text-transform: uppercase; margin-bottom: 20px; }
    .arch-row { display: flex; align-items: center; justify-content: center; gap: 8px; margin: 6px 0; flex-wrap: wrap; }
    .node {
      padding: 8px 16px; border-radius: 6px; font-size: 0.85em; font-weight: bold;
      border: 2px solid transparent;
    }
    .node-browser { background: #1e3a5f; border-color: #4a90d9; color: #7ec8f7; }
    .node-sw     { background: #3a1e5f; border-color: #9b59b6; color: #d7a8f7;
                   box-shadow: 0 0 12px #9b59b655; }
    .node-net    { background: #1e3d2a; border-color: #27ae60; color: #6decaa; opacity: 0.45; }
    .arrow { color: #555; font-size: 1.2em; }
    .arrow-intercepted { color: #9b59b6; font-weight: bold; }
    .intercept-label {
      font-size: 0.7em; color: #9b59b6; background: #2a1a3e;
      border: 1px solid #6a3a9e; border-radius: 4px; padding: 2px 8px; margin-left: 4px;
    }
    .cross { color: #e74c3c; font-weight: bold; font-size: 1.1em; }

    .sw-status {
      display: flex; align-items: center; gap: 10px;
      background: #1a1d27; border: 1px solid #2e3248; border-radius: 8px;
      padding: 14px 18px; margin-bottom: 28px;
    }
    .dot { width: 10px; height: 10px; border-radius: 50%; background: #27ae60;
           box-shadow: 0 0 6px #27ae60; flex-shrink: 0; }
    .sw-status-text { font-size: 0.85em; color: #aaa; }
    .sw-status-text strong { color: #d7a8f7; }

    h1 { font-size: 1.4em; margin-bottom: 6px; }
    .badge { display: inline-block; background: #9b59b6; color: white;
             padding: 3px 10px; border-radius: 4px; font-size: 0.75em; vertical-align: middle; }
    .desc { color: #888; font-size: 0.9em; margin-bottom: 24px; }

    h3 { font-size: 0.95em; color: #aaa; margin-bottom: 10px; }
    .btn {
      background: #9b59b6; color: white; border: none; padding: 10px 20px;
      border-radius: 6px; cursor: pointer; font-size: 0.9em; margin-bottom: 12px;
    }
    .btn:hover { background: #8e44ad; }
    .result-box {
      background: #1a1d27; border: 1px solid #2e3248; border-radius: 6px;
      padding: 14px; font-family: monospace; font-size: 0.85em; min-height: 3em;
      color: #6decaa; white-space: pre-wrap;
    }
    .meta { font-size: 0.75em; color: #555; margin-top: 10px; }
  </style>
</head>
<body>
<div class="container">

  <div class="arch-diagram">
    <h2>リクエストの流れ</h2>
    <div class="arch-row">
      <span class="node node-browser">ブラウザ (fetch)</span>
      <span class="arrow arrow-intercepted">&#8594;</span>
      <span class="node node-sw">Service Worker<br><small>HTTP Server</small></span>
      <span class="intercept-label">intercept</span>
    </div>
    <div class="arch-row" style="margin-top:10px; color:#555; font-size:0.8em;">
      <span class="cross">&#x2715;</span>
      <span style="margin-left:6px;">ネットワークには出ない</span>
      <span class="node node-net" style="margin-left:8px; font-size:0.85em;">外部サーバー</span>
    </div>
  </div>

  <div class="sw-status" id="sw-status">
    <div class="dot" id="sw-dot" style="background:#555; box-shadow:none;"></div>
    <div class="sw-status-text" id="sw-status-text">Service Worker 状態を確認中...</div>
  </div>

  <h1>AtomVM HTTP Server <span class="badge">Service Worker</span></h1>
  <p class="desc">このページ自体も、APIレスポンスも、すべて Service Worker 内の HTTPサーバーが返しています。ネットワーク通信は発生しません。</p>

  <h3>REST API テスト</h3>
  <button class="btn" onclick="fetchStatus()">GET /api/status</button>
  <div class="result-box" id="api-result">ボタンを押してAPIを呼び出す...</div>
  <div class="meta" id="api-meta"></div>

</div>
<script>
  // Service Worker 登録状態を表示
  async function checkSW() {
    const dot = document.getElementById('sw-dot');
    const txt = document.getElementById('sw-status-text');
    if (!('serviceWorker' in navigator)) {
      txt.innerHTML = 'Service Worker は <strong>非対応</strong> のブラウザです';
      return;
    }
    const reg = await navigator.serviceWorker.getRegistration();
    if (reg && reg.active) {
      dot.style.background = '#27ae60';
      dot.style.boxShadow = '0 0 6px #27ae60';
      txt.innerHTML = 'Service Worker <strong>稼働中</strong> — このリクエストはすべて SW 内サーバーが処理しています';
    } else {
      dot.style.background = '#e67e22';
      dot.style.boxShadow = '0 0 6px #e67e22';
      txt.innerHTML = 'Service Worker を <strong>登録中</strong>... ページをリロードしてください';
    }
  }
  checkSW();

  async function fetchStatus() {
    const el = document.getElementById('api-result');
    const meta = document.getElementById('api-meta');
    el.textContent = '送信中...';
    meta.textContent = '';
    const t0 = performance.now();
    try {
      const res = await fetch('/api/status');
      const elapsed = (performance.now() - t0).toFixed(1);
      const data = await res.json();
      el.textContent = JSON.stringify(data, null, 2);
      meta.textContent = 'HTTP ' + res.status + '  •  ' + elapsed + ' ms  •  ネットワーク未使用（Service Worker が応答）';
    } catch (e) {
      el.style.color = '#e74c3c';
      el.textContent = 'Error: ' + e.message;
    }
  }
</script>
</body>
</html>`,

  get(path) {
    if (path === "/" || path === "/index.html") {
      return { ok: true, contentType: "text/html", body: this.indexHtml };
    }
    return { ok: false, error: "not_found" };
  },
};

// --- ApiHandler (api_handler.ex 対応) ---
const ApiHandler = {
  handle(method, path) {
    if (method === "get" && path === "/api/status") {
      return {
        ok: true,
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ status: "ok", vm: "AtomVM", version: "0.1.0" }),
      };
    }
    return { ok: false, error: "not_found" };
  },
};

// --- Router (router.ex 対応) ---
const Router = {
  route(req) {
    // GET /api/status → ApiHandler
    if (req.method === "get" && req.path === "/api/status") {
      return ApiHandler.handle(req.method, req.path);
    }

    // GET → Static
    if (req.method === "get") {
      const result = Static.get(req.path);
      if (result.ok) {
        return { ok: true, status: 200, contentType: result.contentType, body: result.body };
      }
      return { ok: false, status: 404 };
    }

    // Other methods → 405
    return { ok: false, status: 405 };
  },
};

// --- Response (response.ex 対応) ---
const ResponseBuilder = {
  build(result) {
    if (result.ok) {
      return new Response(result.body, {
        status: result.status,
        headers: { "Content-Type": result.contentType + "; charset=utf-8" },
      });
    }

    if (result.status === 404) {
      return new Response("404 Not Found", {
        status: 404,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    return new Response("405 Method Not Allowed", {
      status: 405,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  },
};

// --- fetch イベント = accept_loop 相当 ---
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // SW自身やブラウザ拡張などはネットワークに通す
  if (url.pathname === "/sw.js" || url.origin !== self.location.origin) {
    return;  // event.respondWith を呼ばない → ブラウザがネットワークfetchする
  }

  const req = RequestParser.parse(event.request);
  const result = Router.route(req);
  event.respondWith(ResponseBuilder.build(result));
});

// SW有効化時に即座にクライアントを制御する
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

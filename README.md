# AtomVM HTTP Server (Elixir)

AtomVM上で動くElixir製HTTPサーバー。`:gen_tcp` ベースで外部ライブラリ不要。
静的HTML配信 + REST API対応。

## 構成

```
lib/
  atomvm_http_server.ex          # エントリーポイント (start/0)、TCP accept ループ
  atomvm_http_server/
    request.ex                   # HTTP リクエストパーサー
    router.ex                    # パスルーティング
    response.ex                  # HTTP レスポンスビルダー
    static.ex                    # 静的HTML (モジュール内埋め込み)
mix.exs
```

## セットアップ

### 1. AtomVM のインストール

```bash
# macOS
brew install atomvm

# Linux (ソースビルド)
git clone https://github.com/atomvm/AtomVM.git
cd AtomVM && mkdir build && cd build
cmake .. && make -j4
sudo make install
```

### 2. ExAtomVM (Mix plugin) のインストール

```bash
mix deps.get
```

### 3. ビルド

```bash
mix atomvm.packbeam
```

`atomvm_http_server.avm` が生成される。

### 4. 起動

```bash
atomvm atomvm_http_server.avm
```

ブラウザで http://localhost:8080/ を開く。

## エンドポイント

| Method | Path         | 説明                        |
|--------|--------------|-----------------------------|
| GET    | /            | HTML デモページ              |
| GET    | /index.html  | HTML デモページ              |
| GET    | /api/status  | ステータス JSON              |

## REST API レスポンス例

```json
{
  "status": "ok",
  "vm": "AtomVM",
  "version": "0.1.0"
}
```

## ページ・APIの追加方法

**静的ページを追加**: `lib/atomvm_http_server/static.ex` に `def get/1` 節を追加

```elixir
def get("/about"), do: {:ok, "text/html", "<h1>About</h1>"}
```

**API を追加**: `lib/atomvm_http_server/router.ex` に節を追加

```elixir
def route(%Request{method: :get, path: "/api/hello"}) do
  {:ok, 200, "application/json", ~s({"message":"hello"})}
end
```

## 参考

- [AtomVM](https://github.com/atomvm/AtomVM)
- [ExAtomVM](https://github.com/atomvm/ExAtomVM)

# MicroPhoenix

AtomVM上で動くElixir製HTTPサーバー。`:socket` ベースで外部ライブラリ不要。
静的HTML配信 + REST API対応。
ルーティングは利用側アプリから注入します。

## 構成

```
lib/
  micro_phoenix.ex              # エントリーポイントとサーバー起動
  micro_phoenix/
    application.ex              # Supervisor起動
    registry.ex                 # Router登録
    request.ex                  # HTTP リクエストパーサー
    response.ex                 # HTTP レスポンスビルダー
    static.ex                   # 静的ファイル応答
priv/
  www/
    index.html                  # アプリ側で使う例
mix.exs
```

## セットアップ

### 1. AtomVM のインストール（ソースビルド）

```bash
it clone https://github.com/atomvm/AtomVM.git
cd AtomVM && mkdir build && cd build
cmake .. && make -j4
sudo make install
```

確認:

```bash
atomvm -v
```

### 2. 依存関係を取得する

```bash
mix deps.get
```

### 3. AtomVM 向けチェックを行う

```bash
mix atomvm.check
```

`Supervisor.start_link/2` は古いAtomVMでは `mix atomvm.check` で警告対象になることがありますが、`micro_phoenix` は Supervisor 構成を前提にしています。

### 4. AVM を生成する

```bash
mix atomvm.packbeam
```

`micro_phoenix.avm` が生成されます。

### 5. 利用側アプリで Router を登録する

`micro_phoenix` 自体は HTML や API のルーティングを持たず、アプリ側の起動処理で Router を登録します。`micro_phoenix` は dependency として起動され、`MicroPhoenix.Application` が `children = [MicroPhoenix]` で HTTP サーバーを supervision tree に載せます。

`MicroPhoenix.Registry.register_router/1` は関数を保持し、HTTP サーバーはリクエスト受信時にその関数を呼び出します。

### 6. AtomVM で起動する

標準ライブラリ `atomvmlib.avm` を一緒に渡して起動します。

```bash
atomvm /tmp/AtomVM/build/libs/atomvmlib.avm micro_phoenix.avm
```

起動後は `http://localhost:8080/` を開きます。

## 開発時の確認

ローカルの Elixir でコンパイル確認:

```bash
mix compile
```

AtomVM 向け成果物の生成確認:

```bash
mix atomvm.check
mix atomvm.packbeam
ls -l *.avm
```

## ライブラリ利用

`micro_phoenix` は HTTP サーバーライブラリとして使い、アプリ側が独自 Router を定義します。

```elixir
defmodule MyApp.Router do
  alias MicroPhoenix.Request

  def route(%Request{method: :get, path: "/"}) do
    {:ok, 200, "text/html", :atomvm.read_priv(:my_app, "www/index.html")}
  end

  def route(%Request{method: :get, path: "/api/status"}) do
    {:ok, 200, "application/json", ~s({"status":"ok","vm":"AtomVM","version":"0.1.0"})}
  end

  def route(%Request{}) do
    {:error, 404}
  end
end
```

アプリ側では、起動時に Router 関数を MicroPhoenix.Registry.register_router/1 で登録します。

```elixir
MicroPhoenix.Registry.register_router(&MyApp.Router.route/1)
```

なお、AtomVM 上で `priv/www/index.html` を返す場合はAtomVM未定義の `File.read!/1` ではなく `:atomvm.read_priv/2` を使います。

外部アプリの `Application.start/2` での想定は次の形です。

```elixir
defmodule MicroScaffoldExample.Application do
  use Application

  @impl true
  def start(_type, _args) do
    MicroPhoenix.Registry.register_router(&MicroScaffoldExampleWeb.Router.route/1)

    children = [
      MicroScaffoldExample.Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MicroScaffoldExample.Supervisor)
  end
end
```

## 参考

- [AtomVM](https://github.com/atomvm/AtomVM)
- [ExAtomVM](https://github.com/atomvm/ExAtomVM)

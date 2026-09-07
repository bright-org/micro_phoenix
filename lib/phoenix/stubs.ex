defmodule Phoenix.Flash do
  @moduledoc false
  def get(flash, key) when is_map(flash), do: Map.get(flash, key)
end

defmodule Phoenix.Channel do
  @moduledoc false
  defmacro __using__(_opts), do: :ok
end

defmodule Phoenix.PubSub do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  def broadcast(_server, _topic, _message), do: :ok
  def subscribe(_server, _topic), do: :ok
end

defmodule Phoenix.LiveView do
  @moduledoc false
  defmacro __using__(_opts), do: :ok
end

defmodule Phoenix.LiveComponent do
  @moduledoc false
  defmacro __using__(_opts), do: :ok
end

defmodule Phoenix.LiveView.Router do
  @moduledoc false
  defmacro live(_path, _module, _action \\ nil), do: :ok
  defmacro live_session(_name, _opts \\ [], _block), do: :ok
end

defmodule Phoenix.LiveView.Socket do
  @moduledoc false
end

defmodule Phoenix.LiveView.JS do
  @moduledoc false
  defstruct ops: []

  def show(%__MODULE__{} = js, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:show, opts}]}

  def show(%__MODULE__{} = js, selector) when is_binary(selector),
    do: show(js, to: selector)

  def show(opts) when is_list(opts), do: show(%__MODULE__{}, opts)
  def show(selector) when is_binary(selector), do: show(%__MODULE__{}, to: selector)

  def hide(%__MODULE__{} = js, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:hide, opts}]}

  def hide(%__MODULE__{} = js, selector) when is_binary(selector),
    do: hide(js, to: selector)

  def hide(opts) when is_list(opts), do: hide(%__MODULE__{}, opts)
  def hide(selector) when is_binary(selector), do: hide(%__MODULE__{}, to: selector)

  def toggle(%__MODULE__{} = js, selector),
    do: %{js | ops: js.ops ++ [{:toggle, selector}]}

  def toggle(selector) when is_binary(selector), do: toggle(%__MODULE__{}, selector)

  def dispatch(%__MODULE__{} = js, event, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:dispatch, event, opts}]}

  def dispatch(event, opts \\ [])

  def dispatch(event, opts) when is_binary(event) and is_list(opts),
    do: dispatch(%__MODULE__{}, event, opts)

  def push(%__MODULE__{} = js, event, opts) when is_binary(event) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:push, event, opts}]}

  def push(event, opts \\ [])

  def push(event, opts) when is_binary(event) and is_list(opts),
    do: push(%__MODULE__{}, event, opts)

  def navigate(href) when is_binary(href), do: navigate(%__MODULE__{}, href, [])

  def navigate(href, opts) when is_binary(href) and is_list(opts),
    do: navigate(%__MODULE__{}, href, opts)

  def navigate(%__MODULE__{} = js, href) when is_binary(href),
    do: navigate(js, href, [])

  def navigate(%__MODULE__{} = js, href, opts) when is_binary(href) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:navigate, href, opts}]}

  def patch(href) when is_binary(href), do: patch(%__MODULE__{}, href, [])

  def patch(href, opts) when is_binary(href) and is_list(opts),
    do: patch(%__MODULE__{}, href, opts)

  def patch(%__MODULE__{} = js, href) when is_binary(href),
    do: patch(js, href, [])

  def patch(%__MODULE__{} = js, href, opts) when is_binary(href) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:patch, href, opts}]}

  # Supports both JS.remove_attribute("hidden", to: "...") and
  # hide(...) |> JS.remove_attribute("hidden", to: "...").
  def remove_attribute(js_or_attr, attr_or_opts \\ [])

  def remove_attribute(%__MODULE__{} = js, attr) when not is_list(attr),
    do: remove_attribute(js, attr, [])

  def remove_attribute(attr, opts) when not is_struct(attr) and is_list(opts),
    do: remove_attribute(%__MODULE__{}, attr, opts)

  def remove_attribute(%__MODULE__{} = js, attr, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:remove_attribute, attr, opts}]}

  def set_attribute(js_or_tuple, tuple_or_opts \\ [])

  def set_attribute(%__MODULE__{} = js, tuple) when not is_list(tuple),
    do: set_attribute(js, tuple, [])

  def set_attribute(tuple, opts) when not is_struct(tuple) and is_list(opts),
    do: set_attribute(%__MODULE__{}, tuple, opts)

  def set_attribute(%__MODULE__{} = js, tuple, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:set_attribute, tuple, opts}]}
end

defimpl Phoenix.HTML.Safe, for: Phoenix.LiveView.JS do
  def to_iodata(%Phoenix.LiveView.JS{ops: ops}) do
    # Do not emit raw `"` — attribute values are wrapped in double quotes by HEEx.
    encoded =
      ops
      |> :erlang.term_to_binary()
      |> Base.encode64()

    ["[[COMPAT,", encoded, "]]"]
  end
end

defimpl String.Chars, for: Phoenix.LiveView.JS do
  def to_string(js), do: Phoenix.HTML.Safe.to_iodata(js) |> IO.iodata_to_binary()
end

defmodule Phoenix.LiveView.LiveStream do
  @moduledoc false
  defstruct [:name, :dom_id]
end

defmodule Phoenix.LiveReloader do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

defmodule Phoenix.LiveReloader.Socket do
  @moduledoc false
end

defmodule Phoenix.LiveDashboard.Router do
  @moduledoc false
  defmacro live_dashboard(_path, _opts \\ []), do: :ok
end

defmodule Phoenix.LiveDashboard.RequestLogger do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

defmodule Phoenix.Ecto.CheckRepoStatus do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

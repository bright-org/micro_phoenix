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

  def show(selector, _opts \\ []), do: %__MODULE__{ops: [{:show, selector}]}
  def hide(selector, _opts \\ []), do: %__MODULE__{ops: [{:hide, selector}]}
  def toggle(selector), do: %__MODULE__{ops: [{:toggle, selector}]}
  def dispatch(_event), do: %__MODULE__{ops: []}
  def remove_attribute(_attr, _opts), do: %__MODULE__{ops: []}
  def set_attribute(_tuple, _opts), do: %__MODULE__{ops: []}
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

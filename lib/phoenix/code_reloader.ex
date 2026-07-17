defmodule Phoenix.CodeReloader do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def call(conn, _opts), do: conn

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  # Mix `listeners: [Phoenix.CodeReloader]` sends compile notifications.
  # AtomVM stub: ignore them (no live reload).
  @impl GenServer
  def handle_info({:modules_compiled, _info}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}
end

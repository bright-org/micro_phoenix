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
end

defmodule MicroPhoenix.Registry do
  @name __MODULE__.Server
  @startup_timeout 1_000
  @configured_router Application.compile_env(:micro_phoenix, :router, nil)

  def register_router(route_fn) when is_function(route_fn, 1) do
    call({:register_router, route_fn}, {:error, :timeout})
  end

  def get_router() do
    case fetch_router() do
      {:ok, router} -> router
      :error -> default_router()
    end
  end

  def fetch_router() do
    case call(:get_router, configured_router()) do
      nil -> :error
      router -> {:ok, router}
    end
  end

  def ensure_started() do
    case Process.whereis(@name) do
      nil -> start_registry()
      pid -> {:ok, pid}
    end
  end

  defp start_registry() do
    parent = self()

    pid =
      spawn_link(fn ->
        true = Process.register(self(), @name)
        send(parent, {:registry_started, self()})
        loop(configured_router())
      end)

    receive do
      {:registry_started, ^pid} -> {:ok, pid}
    after
      @startup_timeout -> {:error, :timeout}
    end
  end

  defp call(message, timeout_value) do
    {:ok, pid} = ensure_started()
    ref = make_ref()

    send(pid, {message, self(), ref})

    receive do
      {^ref, response} -> response
    after
      @startup_timeout -> timeout_value
    end
  end

  defp loop(route_fn) do
    receive do
      {{:register_router, next_route_fn}, from, ref} ->
        send(from, {ref, :ok})
        loop(next_route_fn)

      {:get_router, from, ref} ->
        send(from, {ref, route_fn})
        loop(route_fn)
    end
  end

  defp configured_router() do
    case @configured_router do
      nil -> default_router()
      router -> router
    end
  end

  defp default_router() do
    fn _request -> {:error, 404} end
  end
end

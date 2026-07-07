defmodule MicroPhoenix.Registry do
  @router_key :micro_phoenix_router
  @configured_router Application.compile_env(:micro_phoenix, :router, nil)

  def register_router(route_fn) when is_function(route_fn, 1) do
    if function_exported?(:persistent_term, :put, 2) do
      :persistent_term.put(@router_key, route_fn)
    end

    :ok
  end

  def get_router do
    case fetch_router() do
      {:ok, router} -> router
      :error -> raise "micro_phoenix router is not registered"
    end
  end

  def fetch_router do
    case persistent_router() do
      {:ok, router} -> {:ok, router}
      :error -> configured_router()
    end
  end

  defp persistent_router do
    if function_exported?(:persistent_term, :get, 2) do
      case :persistent_term.get(@router_key, nil) do
        nil -> :error
        router -> {:ok, router}
      end
    else
      :error
    end
  end

  defp configured_router do
    case @configured_router do
      nil -> :error
      router -> {:ok, router}
    end
  end
end

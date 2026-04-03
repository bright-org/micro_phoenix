defmodule MicroPhoenix.Registry do
  @router_key :micro_phoenix_router

  def register_router(route_fn) when is_function(route_fn, 1) do
    :persistent_term.put(@router_key, route_fn)
  end

  def get_router do
    :persistent_term.get(@router_key)
  end
end

defmodule Phoenix.Router do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: Macro.escape(opts, unquote: true)] do
      @behaviour Plug

      import Phoenix.Router
      import Plug.Conn

      Module.register_attribute(__MODULE__, :phoenix_pipelines, accumulate: false, persist: true)
      Module.register_attribute(__MODULE__, :current_pipeline_plugs, accumulate: true, persist: false)
      Module.register_attribute(__MODULE__, :phoenix_routes, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :phoenix_scope_prefix, persist: false)
      Module.register_attribute(__MODULE__, :phoenix_scope_alias, persist: false)
      Module.register_attribute(__MODULE__, :phoenix_scope_pipelines, persist: false)

      @phoenix_pipelines %{}
      @phoenix_scope_prefix ""
      @phoenix_scope_alias nil
      @phoenix_scope_pipelines []

      @before_compile Phoenix.Router

      def init(opts), do: opts

      def call(conn, opts) do
        Phoenix.Router.__dispatch__(conn, opts, __MODULE__)
      end
    end
  end

  defmacro pipeline(name, do: block) do
    quote do
      Module.delete_attribute(__MODULE__, :current_pipeline_plugs)
      unquote(block)
      @phoenix_pipelines Map.put(@phoenix_pipelines, unquote(name), Enum.reverse(@current_pipeline_plugs))
      Module.delete_attribute(__MODULE__, :current_pipeline_plugs)
    end
  end

  defmacro plug(plug, opts \\ []) do
    quote do
      @current_pipeline_plugs {unquote(plug), unquote(Macro.escape(opts))}
    end
  end

  defmacro scope(prefix, alias \\ nil, do: block) do
    quote do
      previous_prefix = @phoenix_scope_prefix
      previous_alias = @phoenix_scope_alias
      previous_pipelines = @phoenix_scope_pipelines

      new_prefix =
        case unquote(prefix) do
          "/" -> previous_prefix
          path -> previous_prefix <> path
        end

      @phoenix_scope_prefix new_prefix
      @phoenix_scope_alias unquote(alias) || previous_alias
      unquote(block)
      @phoenix_scope_prefix previous_prefix
      @phoenix_scope_alias previous_alias
      @phoenix_scope_pipelines previous_pipelines
    end
  end

  defmacro pipe_through(pipeline) do
    quote do
      @phoenix_scope_pipelines unquote(pipeline)
    end
  end

  defmacro get(path, controller, action) do
    quote do
      @phoenix_routes {:get, @phoenix_scope_prefix <> unquote(path), unquote(controller),
                       unquote(action), @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro post(path, controller, action) do
    quote do
      @phoenix_routes {:post, @phoenix_scope_prefix <> unquote(path), unquote(controller),
                       unquote(action), @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro put(path, controller, action) do
    quote do
      @phoenix_routes {:put, @phoenix_scope_prefix <> unquote(path), unquote(controller),
                       unquote(action), @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro patch(path, controller, action) do
    quote do
      @phoenix_routes {:patch, @phoenix_scope_prefix <> unquote(path), unquote(controller),
                       unquote(action), @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro delete(path, controller, action) do
    quote do
      @phoenix_routes {:delete, @phoenix_scope_prefix <> unquote(path), unquote(controller),
                       unquote(action), @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro forward(path, plug) do
    quote do
      @phoenix_routes {:forward, @phoenix_scope_prefix <> unquote(path), unquote(plug), nil,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro resources(path, controller) do
    quote bind_quoted: [path: path, controller: controller] do
      @phoenix_routes {:get, @phoenix_scope_prefix <> path, controller, :index, @phoenix_scope_alias,
                       @phoenix_scope_pipelines}
      @phoenix_routes {:get, @phoenix_scope_prefix <> path <> "/new", controller, :new,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:post, @phoenix_scope_prefix <> path, controller, :create,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:get, @phoenix_scope_prefix <> path <> "/:id", controller, :show,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:get, @phoenix_scope_prefix <> path <> "/:id/edit", controller, :edit,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:put, @phoenix_scope_prefix <> path <> "/:id", controller, :update,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:patch, @phoenix_scope_prefix <> path <> "/:id", controller, :update,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
      @phoenix_routes {:delete, @phoenix_scope_prefix <> path <> "/:id", controller, :delete,
                       @phoenix_scope_alias, @phoenix_scope_pipelines}
    end
  end

  defmacro __before_compile__(env) do
    pipelines = Module.get_attribute(env.module, :phoenix_pipelines) || %{}
    routes = Enum.reverse(Module.get_attribute(env.module, :phoenix_routes) || [])

    quote do
      def __phoenix_pipelines__, do: unquote(Macro.escape(pipelines))
      def __phoenix_routes__, do: unquote(Macro.escape(routes))
    end
  end

  def __dispatch__(conn, _opts, router) do
    routes = router.__phoenix_routes__()
    pipelines = router.__phoenix_pipelines__()

    case match_route(conn.method, conn.request_path, routes) do
      {:ok, controller, action, path_params, pipeline_name} ->
        conn =
          conn
          |> run_pipeline(pipelines, pipeline_name, router)
          |> Map.put(:path_params, path_params)
          |> Map.put(:params, Map.merge(conn.params, path_params))
          |> Plug.Conn.put_private(:phoenix_controller, controller)
          |> Plug.Conn.put_private(:phoenix_action, action)

        controller |> resolve_controller(conn) |> apply(action, [conn, conn.params])

      {:forward, plug, path_params, pipeline_name} ->
        conn =
          conn
          |> run_pipeline(pipelines, pipeline_name, router)
          |> Map.put(:path_params, path_params)
          |> Map.put(:params, Map.merge(conn.params, path_params))

        plug.call(conn, plug.init([]))

      :error ->
        conn
        |> Plug.Conn.send_resp(404, "Not Found")
        |> Plug.Conn.halt()
    end
  end

  defp run_pipeline(conn, _pipelines, nil, _router), do: conn

  defp run_pipeline(conn, pipelines, pipeline_name, router) do
    Enum.reduce(pipelines[pipeline_name] || [], conn, fn {plug, opts}, acc ->
      case plug do
        plug when is_atom(plug) and plug in [:accepts, :fetch_session, :fetch_live_flash, :put_root_layout, :put_layout, :protect_from_forgery, :put_secure_browser_headers] ->
          apply(Phoenix.Controller, plug, [acc, opts])

        plug when is_atom(plug) ->
          if function_exported?(router, plug, 2) do
            apply(router, plug, [acc, opts])
          else
            acc
          end

        module when is_atom(module) ->
          module.call(acc, opts)
      end
    end)
  end

  defp match_route(method, path, routes) do
    method = Phoenix.Binary.http_method_atom(to_string(method))

    Enum.find_value(routes, :error, fn
      {:forward, pattern, plug, _action, _alias, pipeline} ->
        case match_path(pattern, path) do
          {:ok, path_params} -> {:forward, plug, path_params, pipeline}
          :error -> false
        end

      {^method, pattern, controller, action, alias, pipeline} ->
        case match_path(pattern, path) do
          {:ok, path_params} ->
            {:ok, expand_controller(controller, alias), action, path_params, pipeline}

          :error ->
            false
        end

      _other ->
        false
    end)
  end

  defp expand_controller(controller, nil), do: controller

  defp expand_controller(controller, alias) when is_atom(controller) and is_atom(alias) do
    # Avoid Module.concat/2 on AtomVM.
    alias_parts =
      alias
      |> Atom.to_string()
      |> then(fn
        <<"Elixir.", rest::binary>> -> rest
        other -> other
      end)
      |> Phoenix.Binary.split(".")

    controller_name =
      controller
      |> Atom.to_string()
      |> then(fn
        <<"Elixir.", rest::binary>> -> rest
        other -> other
      end)
      |> Phoenix.Binary.split(".")
      |> List.last()

    ("Elixir." <> Enum.join(alias_parts ++ [controller_name], "."))
    |> :erlang.binary_to_atom(:utf8)
  end

  defp match_path(pattern, path) do
    pattern_parts = Phoenix.Binary.split_trim(pattern, "/")
    path_parts = Phoenix.Binary.split_trim(path, "/")

    if length(pattern_parts) == length(path_parts) do
      match_parts(zip_parts(pattern_parts, path_parts), %{})
    else
      :error
    end
  end

  # AtomVM Enum lacks zip/2 and reduce_while/3.
  defp zip_parts([a | as], [b | bs]), do: [{a, b} | zip_parts(as, bs)]
  defp zip_parts([], []), do: []
  defp zip_parts(_, _), do: []

  defp match_parts([{":" <> key, value} | rest], acc) do
    match_parts(rest, Map.put(acc, key, value))
  end

  defp match_parts([{same, same} | rest], acc) do
    match_parts(rest, acc)
  end

  defp match_parts([_ | _], _acc), do: :error
  defp match_parts([], acc), do: {:ok, acc}

  defp resolve_controller(controller, conn) do
    Map.get(conn.private, :phoenix_router_controller) || controller
  end
end

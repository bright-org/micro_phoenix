defmodule MicroPhoenix.Router do
  defmacro __using__(_opts) do
    quote do
      import MicroPhoenix.Router
      Module.register_attribute(__MODULE__, :micro_phoenix_routes, accumulate: true)
      @before_compile MicroPhoenix.Router
    end
  end

  defmacro get(path, controller, action) do
    quote do
      @micro_phoenix_routes {:get, unquote(path), unquote(controller), unquote(action)}
    end
  end

  defmacro post(path, controller, action) do
    quote do
      @micro_phoenix_routes {:post, unquote(path), unquote(controller), unquote(action)}
    end
  end

  defmacro put(path, controller, action) do
    quote do
      @micro_phoenix_routes {:put, unquote(path), unquote(controller), unquote(action)}
    end
  end

  defmacro patch(path, controller, action) do
    quote do
      @micro_phoenix_routes {:patch, unquote(path), unquote(controller), unquote(action)}
    end
  end

  defmacro delete(path, controller, action) do
    quote do
      @micro_phoenix_routes {:delete, unquote(path), unquote(controller), unquote(action)}
    end
  end

  defmacro resources(path, controller) do
    quote bind_quoted: [path: path, controller: controller] do
      @micro_phoenix_routes {:get, path, controller, :index}
      @micro_phoenix_routes {:get, path <> "/new", controller, :new}
      @micro_phoenix_routes {:post, path, controller, :create}
      @micro_phoenix_routes {:get, path <> "/:id", controller, :show}
      @micro_phoenix_routes {:get, path <> "/:id/edit", controller, :edit}
      @micro_phoenix_routes {:put, path <> "/:id", controller, :update}
      @micro_phoenix_routes {:patch, path <> "/:id", controller, :update}
      @micro_phoenix_routes {:delete, path <> "/:id", controller, :delete}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def dispatch(%MicroPhoenix.Request{} = request) do
        request
        |> MicroPhoenix.Conn.from_request()
        |> MicroPhoenix.Conn.merge_params()
        |> dispatch_conn()
      end

      def routes, do: @micro_phoenix_routes |> Enum.reverse()

      defp dispatch_conn(%MicroPhoenix.Conn{} = conn) do
        case MicroPhoenix.Static.serve(conn.path) do
          {:ok, content_type, body} ->
            MicroPhoenix.Response.build({:ok, 200, content_type, body})

          :not_found ->
            case match_route(conn.method, conn.path, routes()) do
              {:ok, controller, action, path_params} ->
                conn =
                  conn
                  |> Map.put(:path_params, path_params)
                  |> Map.put(:params, Map.merge(conn.params, path_params))
                  |> Map.update!(:private, &Map.put(&1, :controller, controller))

                controller |> apply(action, [conn, conn.params]) |> MicroPhoenix.Response.build()

              :error ->
                MicroPhoenix.Response.build({:error, 404})
            end
        end
      end

      defp match_route(method, path, routes) do
        Enum.reduce_while(routes, :error, fn {route_method, pattern, controller, action}, _acc ->
          if route_method == method do
            case match_path(pattern, path) do
              {:ok, path_params} -> {:halt, {:ok, controller, action, path_params}}
              :error -> {:cont, :error}
            end
          else
            {:cont, :error}
          end
        end)
      end

      defp match_path(pattern, path) do
        pattern_parts = String.split(pattern, "/", trim: true)
        path_parts = String.split(path, "/", trim: true)

        if length(pattern_parts) == length(path_parts) do
          Enum.zip(pattern_parts, path_parts)
          |> Enum.reduce_while({:ok, %{}}, fn
            {":" <> key, value}, {:ok, acc} ->
              {:cont, {:ok, Map.put(acc, key, value)}}

            {same, same}, acc ->
              {:cont, acc}

            _, _ ->
              {:halt, :error}
          end)
        else
          :error
        end
      end
    end
  end
end

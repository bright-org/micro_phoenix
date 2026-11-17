defmodule Phoenix.AtomVM do
  @moduledoc """
  Generic AtomVM HTTP accept loop for Phoenix-compatible routers.

  Prefer wiring via the host project's `mix.exs` (no app `lib/` start module):

      atomvm: [
        start: Phoenix.AtomVM.Boot,
        router: MyAppWeb.Router,
        endpoint: MyAppWeb.Endpoint,
        repo: MyApp.Repo,
        port: 8080
      ]

  Then:

      mix phoenix.atomvm.packbeam
      mix phoenix.atomvm.run

  For explicit migrations (host timing equivalent of pending migrate):

      mix ecto.migrate

  `:endpoint` routes HTTP through the Endpoint Plug chain; without it, HTTP
  continues to dispatch directly to `:router`.

  `mix phoenix.atomvm.packbeam` generates `Phoenix.AtomVM.Boot` into the app ebin
  (ExAtomVM requires the start beam there) and packs the AVM. You can also call
  `run/2` / `migrate/3` directly from tests.
  """

  @header_limit 65_536
  @recv_timeout 5_000

  def run(router, opts \\ []) when is_atom(router) and is_list(opts) do
    port = Keyword.get(opts, :port, 8080)
    endpoint = Keyword.get(opts, :endpoint)
    repo = Keyword.get(opts, :repo)
    otp_app = Keyword.get(opts, :otp_app)
    repo_config = Keyword.get(opts, :repo_config, [])

    static = Keyword.get(opts, :static, [])
    socket_mount = Keyword.get(opts, :socket)
    static = Keyword.put_new(static, :only, ~w(assets fonts images favicon.ico robots.txt))

    static =
      if otp_app do
        Keyword.put_new(static, :otp_app, otp_app)
      else
        static
      end

    if repo do
      ensure_ecto_stack_started()
      ensure_repo_started(repo, repo_config)
    end

    case listen_socket(port) do
      {:ok, sock} ->
        IO.puts("AtomVM Phoenix listening on http://localhost:#{port}/")
        accept_loop(sock, router, static, socket_mount, endpoint)

      {:error, :eaddrinuse} ->
        :erlang.display({:listen_failed, :eaddrinuse, port})

        IO.puts(
          "error: port #{port} already in use. Stop the other process (e.g. pkill -f AtomVM) and retry."
        )

        :error

      {:error, {:bind, 98}} ->
        :erlang.display({:listen_failed, :eaddrinuse, port})

        IO.puts(
          "error: port #{port} already in use. Stop the other process (e.g. pkill -f AtomVM) and retry."
        )

        :error

      {:error, reason} ->
        :erlang.display({:listen_failed, reason, port})
        IO.puts("error: failed to listen on port #{port}: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Runs migrations on AtomVM via `Ecto.Migrator` (tuple source, no Mix / no `.exs` load).

  `migrations` is a list of `{version, module}` as accepted by `Ecto.Migrator.run/4`.
  """
  def migrate(repo, migrations, opts \\ [])
      when is_atom(repo) and is_list(migrations) and is_list(opts) do
    repo_config = Keyword.get(opts, :repo_config, [])

    ensure_ecto_stack_started()
    ensure_repo_started(repo, repo_config)

    migrator_opts =
      opts
      |> Keyword.take([
        :all,
        :step,
        :to,
        :to_exclusive,
        :log,
        :log_migrations_sql,
        :log_migrator_sql,
        :prefix,
        :strict_version_order
      ])
      |> then(fn taken ->
        if taken[:to] || taken[:to_exclusive] || taken[:step] || taken[:all] do
          taken
        else
          Keyword.put(taken, :all, true)
        end
      end)
      # AtomVM: advisory migration lock path is not reliable; keep unlocked.
      |> Keyword.put_new(:migration_lock, false)
      |> Keyword.put_new(:log, :info)

    try do
      Ecto.Migrator.run(repo, migrations, :up, migrator_opts)
    rescue
      e ->
        :erlang.display({:migrate_error, Exception.message(e)})
        {:error, e}
    catch
      kind, reason ->
        :erlang.display({:migrate_catch, kind, reason})
        {:error, {kind, reason}}
    end
  end

  defp listen_socket(port) do
    with {:ok, socket} <- :socket.open(:inet, :stream, :tcp),
         :ok <- :socket.setopt(socket, {:socket, :reuseaddr}, true),
         :ok <- :socket.bind(socket, %{family: :inet, port: port, addr: :any}),
         :ok <- :socket.listen(socket) do
      {:ok, socket}
    end
  end

  defp ensure_ecto_stack_started do
    Enum.each(
      [
        Ecto.Application,
        DBConnection.App,
        Postgrex.App,
        Ecto.Adapters.SQL.Application
      ],
      fn mod ->
        case mod.start(:normal, []) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          other -> :erlang.display({:ecto_stack_start_failed, mod, other})
        end
      end
    )
  end

  defp ensure_repo_started(repo, repo_config) do
    case repo.start_link(repo_config) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      other ->
        :erlang.display({:repo_start_failed, other})
        raise "repo start_link failed: #{inspect(other)}"
    end
  end

  defp accept_loop(listen_sock, router, static, socket_mount, endpoint) do
    case :socket.accept(listen_sock) do
      {:ok, client} ->
        spawn(fn -> handle_client(client, router, static, socket_mount, endpoint) end)
        accept_loop(listen_sock, router, static, socket_mount, endpoint)

      {:error, _reason} ->
        accept_loop(listen_sock, router, static, socket_mount, endpoint)
    end
  end

  defp handle_client(socket, router, static, socket_mount, endpoint) do
    case recv_http_request(socket) do
      {:ok, data, buffered} ->
        case socket_target(data, socket_mount) do
          {:socket, socket_module, opts} ->
            _ = Phoenix.WebSocket.serve(socket, data, buffered, socket_module, opts)
            _ = :socket.close(socket)

          :http ->
            handle_http(socket, data, router, static, endpoint)
        end

      {:error, reason} ->
        :erlang.display({:recv_failed, reason})
        _ = :socket.close(socket)
    end
  rescue
    e ->
      :erlang.display({:handle_client_outer_error, e})
      _ = :socket.close(socket)
  catch
    kind, reason ->
      :erlang.display({:handle_client_outer_catch, kind, reason})
      _ = :socket.close(socket)
  end

  @doc false
  def socket_target(_data, nil), do: :http

  def socket_target(data, mount) when is_tuple(mount), do: socket_target(data, [mount])

  def socket_target(data, mounts) when is_list(mounts) do
    [request_line | _] = Phoenix.Binary.split2(data, "\r\n")

    case Phoenix.Binary.split(request_line, " ") do
      [_method, target, _version] ->
        [request_path | _] = Phoenix.Binary.split2(target, "?")

        Enum.find_value(mounts, :http, fn mount ->
          {path, module, opts} = normalize_mount(mount)

          if request_path == path or request_path == path <> "/websocket" do
            {:socket, module, opts}
          end
        end)

      _ ->
        :http
    end
  end

  defp normalize_mount({path, module}), do: {path, module, []}
  defp normalize_mount({path, module, opts}), do: {path, module, opts}

  defp handle_http(socket, data, router, static, endpoint) do
    response =
      try do
        dispatch =
          if endpoint do
            Phoenix.Endpoint.Server.dispatch(data, endpoint)
          else
            Phoenix.Endpoint.Server.dispatch_router(data, router, static: static)
          end

        case dispatch do
          {:ok, resp} ->
            resp

          error ->
            :erlang.display({:dispatch_failed, error})
            http_error(500, "Internal Server Error")
        end
      rescue
        _e in Ecto.NoResultsError ->
          http_error(404, "Not Found")

        _e in Ecto.CastError ->
          http_error(400, "Bad Request")

        e ->
          :erlang.display({:handle_client_error, e, __STACKTRACE__})

          status =
            case e do
              %{plug_status: status}
              when is_integer(status) and status >= 400 and status <= 599 ->
                status

              _ ->
                500
            end

          http_error(status, Plug.Conn.Status.reason_phrase(status))
      catch
        kind, reason ->
          :erlang.display({:handle_client_catch, kind, reason})
          http_error(500, "Internal Server Error")
      end

    _ = socket_send(socket, response)
    _ = :socket.close(socket)
  end

  defp recv_http_request(socket), do: recv_http_request(socket, <<>>)

  defp recv_http_request(socket, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [header_part, _body] when byte_size(header_part) > @header_limit ->
        {:error, :header_too_large}

      [header_part, body] ->
        content_length = content_length_from_headers(header_part)

        cond do
          byte_size(body) >= content_length ->
            request = header_part <> "\r\n\r\n" <> binary_part(body, 0, content_length)
            extra = binary_part(body, content_length, byte_size(body) - content_length)
            {:ok, request, extra}

          true ->
            case :socket.recv(socket, 0, @recv_timeout) do
              {:ok, chunk} -> recv_http_request(socket, acc <> chunk)
              {:error, reason} -> {:error, reason}
            end
        end

      [_] when byte_size(acc) > @header_limit ->
        {:error, :header_too_large}

      [_] ->
        case :socket.recv(socket, 0, @recv_timeout) do
          {:ok, chunk} -> recv_http_request(socket, acc <> chunk)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp socket_send(socket, data) when is_binary(data) do
    case :socket.send(socket, data) do
      :ok -> :ok
      {:ok, <<>>} -> :ok
      {:ok, rest} -> socket_send(socket, rest)
      {:error, _} = error -> error
    end
  end

  defp socket_send(socket, data), do: socket_send(socket, IO.iodata_to_binary(data))

  defp http_error(status, body) when is_integer(status) and is_binary(body) do
    reason = Plug.Conn.Status.reason_phrase(status)

    "HTTP/1.1 #{status} #{reason}\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <> body
  end

  defp content_length_from_headers(header_part) do
    content_length_from_lines(:binary.split(header_part, "\r\n", [:global]))
  end

  defp content_length_from_lines([line | rest]) do
    case :binary.split(Phoenix.Binary.downcase_ascii(line), "content-length:") do
      [_, value] ->
        case Phoenix.Binary.parse_integer(trim_ascii(value)) do
          {n, _} when n >= 0 -> n
          _ -> content_length_from_lines(rest)
        end

      _ ->
        content_length_from_lines(rest)
    end
  end

  defp content_length_from_lines([]), do: 0

  defp trim_ascii(bin) when is_binary(bin) do
    bin
    |> trim_leading_ascii()
    |> trim_trailing_ascii()
  end

  defp trim_leading_ascii(<<" ", rest::binary>>), do: trim_leading_ascii(rest)
  defp trim_leading_ascii(<<"\t", rest::binary>>), do: trim_leading_ascii(rest)
  defp trim_leading_ascii(bin), do: bin

  defp trim_trailing_ascii(bin) do
    size = byte_size(bin)

    cond do
      size == 0 ->
        bin

      binary_part(bin, size - 1, 1) in [" ", "\t"] ->
        trim_trailing_ascii(binary_part(bin, 0, size - 1))

      true ->
        bin
    end
  end
end

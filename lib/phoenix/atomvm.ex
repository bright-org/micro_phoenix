defmodule Phoenix.AtomVM do
  @moduledoc """
  Generic AtomVM HTTP accept loop for Phoenix-compatible routers.

  Prefer wiring via the host project's `mix.exs` (no app `lib/` start module):

      atomvm: [
        start: Phoenix.AtomVM.Boot,
        router: MyAppWeb.Router,
        repo: MyApp.Repo,
        port: 8080
      ]

  Then:

      mix phoenix.atomvm.packbeam
      mix phoenix.atomvm.run

  `mix phoenix.atomvm.packbeam` generates `Phoenix.AtomVM.Boot` into the app ebin
  (ExAtomVM requires the start beam there) and packs the AVM. You can also call
  `run/2` directly from tests.
  """

  @header_limit 65_536
  @recv_timeout 5_000

  def run(router, opts \\ []) when is_atom(router) and is_list(opts) do
    port = Keyword.get(opts, :port, 8080)
    repo = Keyword.get(opts, :repo)
    otp_app = Keyword.get(opts, :otp_app)
    repo_config = Keyword.get(opts, :repo_config, [])

    static = Keyword.get(opts, :static, [])
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

    case :gen_tcp.listen(port, [:binary, {:active, false}, {:reuseaddr, true}, {:packet, :raw}]) do
      {:ok, sock} ->
        IO.puts("AtomVM Phoenix listening on http://localhost:#{port}/")
        accept_loop(sock, router, static)

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
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
      other -> :erlang.display({:repo_start_failed, other})
    end
  rescue
    e -> :erlang.display({:repo_start_error, Exception.message(e)})
  catch
    kind, reason -> :erlang.display({:repo_start_catch, kind, reason})
  end

  defp accept_loop(listen_sock, router, static) do
    case :gen_tcp.accept(listen_sock) do
      {:ok, client} ->
        spawn(fn -> handle_client(client, router, static) end)
        accept_loop(listen_sock, router, static)

      {:error, _reason} ->
        accept_loop(listen_sock, router, static)
    end
  end

  defp handle_client(socket, router, static) do
    case recv_http_request(socket) do
      {:ok, data} ->
        response =
          try do
            case Phoenix.Endpoint.Server.dispatch_router(data, router, static: static) do
              {:ok, resp} ->
                resp

              error ->
                :erlang.display({:dispatch_failed, error})
                "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\n\r\nInternal Server Error"
            end
          catch
            {:ecto_no_results, _queryable, _id} ->
              "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"

            kind, reason ->
              :erlang.display({:handle_client_catch, kind, reason})
              "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\n\r\nInternal Server Error"
          rescue
            e ->
              :erlang.display({:handle_client_error, e, __STACKTRACE__})
              "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\n\r\nInternal Server Error"
          end

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

      {:error, reason} ->
        :erlang.display({:recv_failed, reason})
        :gen_tcp.close(socket)
    end
  rescue
    e ->
      :erlang.display({:handle_client_outer_error, e})
      :gen_tcp.close(socket)
  catch
    kind, reason ->
      :erlang.display({:handle_client_outer_catch, kind, reason})
      :gen_tcp.close(socket)
  end

  defp recv_http_request(socket), do: recv_http_request(socket, <<>>)

  defp recv_http_request(_socket, acc) when byte_size(acc) > @header_limit do
    {:error, :header_too_large}
  end

  defp recv_http_request(socket, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [header_part, body] ->
        content_length = content_length_from_headers(header_part)

        cond do
          byte_size(body) >= content_length ->
            {:ok, header_part <> "\r\n\r\n" <> binary_part(body, 0, content_length)}

          true ->
            case :gen_tcp.recv(socket, 0, @recv_timeout) do
              {:ok, chunk} -> recv_http_request(socket, acc <> chunk)
              {:error, reason} -> {:error, reason}
            end
        end

      [_] ->
        case :gen_tcp.recv(socket, 0, @recv_timeout) do
          {:ok, chunk} -> recv_http_request(socket, acc <> chunk)
          {:error, reason} -> {:error, reason}
        end
    end
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

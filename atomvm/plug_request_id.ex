defmodule Plug.RequestId do
  @behaviour Plug

  # TODO: AtomVM Plug.RequestId preserves ID generation, forwarding, response headers, and the Plug.Conn return value. Automatic correlation of subsequent logs via Logger.metadata is not supported.
  def init(opts) do
    {
      Keyword.get(opts, :http_header, "x-request-id"),
      Keyword.get(opts, :assign_as),
      Keyword.get(opts, :logger_metadata_key, :request_id),
      Keyword.get(opts, :generator, &__MODULE__.generate/0)
    }
  end

  def call(conn, {header, assign_as, logger_metadata_key, generator}) do
    request_id =
      case Plug.Conn.get_req_header(conn, header) do
        [val | _] when byte_size(val) in 20..200 -> val
        _ -> generator.()
      end

    IO.puts("#{logger_metadata_key}=#{request_id}")
    conn = if assign_as, do: Plug.Conn.assign(conn, assign_as, request_id), else: conn
    Plug.Conn.put_resp_header(conn, header, request_id)
  end

  def generate do
    timestamp = System.system_time(:nanosecond)
    counter = :erlang.unique_integer()
    Base.url_encode64(<<timestamp::64, counter::64>>, padding: false)
  end
end

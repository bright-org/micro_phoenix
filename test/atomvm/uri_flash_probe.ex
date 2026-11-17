defmodule MicroPhoenix.URIFlashProbe do
  def start do
    conn = %MicroPhoenix.Conn{halted: true, flash: %{"info" => "a b"}, resp_body: "ok"}
    response = MicroPhoenix.Response.build(conn)

    if :binary.match(response, "Set-Cookie: _micro_flash=info=a+b; Path=/") != :nomatch do
      :erlang.display(:uri_flash_ok)
      :ok
    else
      :erlang.error({:unexpected_response, response})
    end
  end
end

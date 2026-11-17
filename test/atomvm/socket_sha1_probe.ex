defmodule MicroPhoenix.SocketSHA1Probe do
  def start do
    for {length, expected} <- [
          {0, "2jmj7l5rSw0yVb/vlWAYkK/YBwk="},
          {55, "wci73CJ5bijA4VFj0giZtlYh1lo="},
          {56, "wtszD2CDhUyZ1LW/tujynyAb5pk="},
          {60, "E9lWAz2a9Em/4sTveMF8IEacS/E="},
          {64, "AJi6gktcFkJ716ESKlpEKiXsZE0="},
          {120, "80wUiDhTRqVXCboFbd0IKA3UxtY="}
        ] do
      send(self(), {:input, :binary.copy("a", length)})

      receive do
        {:input, message} ->
          actual = Phoenix.WebSocket.SHA1.hash(message) |> Base.encode64()
          if actual != expected, do: :erlang.error({:sha1_mismatch, length, actual})
      end
    end

    :erlang.display(:socket_sha1_ok)
    :ok
  end
end

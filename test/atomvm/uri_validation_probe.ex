defmodule AtomVM.URI.ValidationProbe do
  def start do
    send(self(), {:invalid, "http://[notipv6]/"})
    send(self(), {:invalid, "http://foo\\bar/"})
    send(self(), {:valid, "http://[::ffff:192.0.2.1]/"})

    receive do
      {:invalid, url} ->
        try do
          AtomVM.URI.new!(url)
          :erlang.error(:invalid_uri_accepted)
        rescue
          AtomVM.URI.Error -> :ok
        end
    end

    receive do
      {:invalid, url} ->
        try do
          AtomVM.URI.new!(url)
          :erlang.error(:invalid_uri_accepted)
        rescue
          AtomVM.URI.Error -> :ok
        end
    end

    receive do
      {:valid, url} ->
        uri = AtomVM.URI.new!(url)
        "::ffff:192.0.2.1" = uri.host
    end

    :erlang.display(:uri_validation_ok)
    :ok
  end
end

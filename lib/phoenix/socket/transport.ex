defmodule Phoenix.Socket.Transport do
  @moduledoc false

  def handle(data, {socket_module, socket, channels} = state) do
    try do
      case :json.decode(data) do
        [join_ref, ref, topic, event, payload]
        when (is_binary(join_ref) or is_nil(join_ref)) and is_binary(ref) and
               is_binary(topic) and is_binary(event) and is_map(payload) ->
          dispatch(join_ref, ref, topic, event, payload, socket_module, socket, channels)

        _ ->
          {:error, state}
      end
    rescue
      _ -> {:error, state}
    catch
      _, _ -> {:error, state}
    end
  end

  defp dispatch(join_ref, ref, topic, "phx_join", payload, socket_module, socket, channels) do
    if Map.has_key?(channels, topic) do
      reply(
        join_ref,
        ref,
        topic,
        "error",
        %{"reason" => "already_joined"},
        channels,
        socket_module,
        socket
      )
    else
      case socket_module.__channel_for__(topic) do
        nil ->
          reply(
            join_ref,
            ref,
            topic,
            "error",
            %{"reason" => "unmatched_topic"},
            channels,
            socket_module,
            socket
          )

        channel ->
          joined_socket = %{socket | topic: topic, join_ref: join_ref}

          case channel.join(topic, payload, joined_socket) do
            {:ok, next_socket} ->
              joined_reply(
                join_ref,
                ref,
                topic,
                %{},
                channels,
                channel,
                next_socket,
                socket_module,
                socket
              )

            {:ok, response, next_socket} when is_map(response) ->
              joined_reply(
                join_ref,
                ref,
                topic,
                response,
                channels,
                channel,
                next_socket,
                socket_module,
                socket
              )

            {:error, response} when is_map(response) ->
              reply(join_ref, ref, topic, "error", response, channels, socket_module, socket)
          end
      end
    end
  end

  defp dispatch(join_ref, ref, topic, "phx_leave", _payload, socket_module, socket, channels) do
    case Map.get(channels, topic) do
      {_channel, channel_socket} when channel_socket.join_ref == join_ref ->
        result =
          case channel_socket.pubsub_server do
            nil -> :ok
            server -> Phoenix.PubSub.unsubscribe(server, topic)
          end

        case result do
          :ok ->
            reply(
              join_ref,
              ref,
              topic,
              "ok",
              %{},
              Map.delete(channels, topic),
              socket_module,
              socket
            )

          _ ->
            reply(
              join_ref,
              ref,
              topic,
              "error",
              %{"reason" => "unsubscribe_failed"},
              channels,
              socket_module,
              socket
            )
        end

      _ ->
        reply(
          join_ref,
          ref,
          topic,
          "error",
          %{"reason" => "unmatched_topic"},
          channels,
          socket_module,
          socket
        )
    end
  end

  defp dispatch(join_ref, ref, topic, event, payload, socket_module, socket, channels) do
    case Map.get(channels, topic) do
      {channel, channel_socket} when channel_socket.join_ref == join_ref ->
        case channel.handle_in(event, payload, channel_socket) do
          {:reply, {status, response}, next_socket}
          when status in [:ok, :error] and is_map(response) ->
            reply(
              join_ref,
              ref,
              topic,
              if(status == :ok, do: "ok", else: "error"),
              response,
              Map.put(channels, topic, {channel, next_socket}),
              socket_module,
              socket
            )

          {:noreply, next_socket} ->
            {:noreply, {socket_module, socket, Map.put(channels, topic, {channel, next_socket})}}
        end

      _ ->
        reply(
          join_ref,
          ref,
          topic,
          "error",
          %{"reason" => "unmatched_topic"},
          channels,
          socket_module,
          socket
        )
    end
  end

  defp joined_reply(
         join_ref,
         ref,
         topic,
         response,
         channels,
         channel,
         next_socket,
         socket_module,
         socket
       ) do
    case next_socket.pubsub_server do
      nil ->
        reply(
          join_ref,
          ref,
          topic,
          "ok",
          response,
          Map.put(channels, topic, {channel, next_socket}),
          socket_module,
          socket
        )

      server ->
        case Phoenix.PubSub.subscribe(server, topic) do
          :ok ->
            reply(
              join_ref,
              ref,
              topic,
              "ok",
              response,
              Map.put(channels, topic, {channel, next_socket}),
              socket_module,
              socket
            )

          _ ->
            reply(
              join_ref,
              ref,
              topic,
              "error",
              %{"reason" => "subscribe_failed"},
              channels,
              socket_module,
              socket
            )
        end
    end
  end

  defp reply(join_ref, ref, topic, status, response, channels, socket_module, socket) do
    payload =
      :json.encode([
        join_ref,
        ref,
        topic,
        "phx_reply",
        %{"status" => status, "response" => response}
      ])

    {:reply, :erlang.iolist_to_binary(payload), {socket_module, socket, channels}}
  end
end

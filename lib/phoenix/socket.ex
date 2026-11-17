defmodule Phoenix.Socket do
  @moduledoc false
  defstruct assigns: %{},
            transport_pid: nil,
            pubsub_server: nil,
            topic: nil,
            join_ref: nil

  defmacro __using__(_opts) do
    quote do
      import Phoenix.Socket, only: [channel: 2]
      Module.register_attribute(__MODULE__, :phoenix_channels, accumulate: true)
      @before_compile Phoenix.Socket
    end
  end

  defmacro channel(topic, module) do
    quote do
      @phoenix_channels {unquote(topic), unquote(module)}
    end
  end

  defmacro __before_compile__(env) do
    channels = env.module |> Module.get_attribute(:phoenix_channels) |> Enum.reverse()

    quote do
      def __channel_for__(topic),
        do: Phoenix.Socket.find_channel(topic, unquote(Macro.escape(channels)))
    end
  end

  def find_channel(_topic, []), do: nil
  def find_channel(topic, [{topic, module} | _]), do: module
  def find_channel(topic, [_ | remaining]), do: find_channel(topic, remaining)

  def assign(%__MODULE__{} = socket, key, value) do
    %{socket | assigns: Map.put(socket.assigns, key, value)}
  end
end

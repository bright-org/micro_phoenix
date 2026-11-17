defmodule Phoenix.Socket.Broadcast do
  @moduledoc false
  defstruct [:topic, :event, :payload]
end

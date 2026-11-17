defmodule Phoenix.WebSocket.SHA1Test do
  use ExUnit.Case, async: true

  test "matches SHA-1 across block and padding boundaries" do
    for length <- [0, 1, 3, 55, 56, 60, 63, 64, 65, 119, 120, 128] do
      data = :binary.copy("a", length)
      assert Phoenix.WebSocket.SHA1.hash(data) == :crypto.hash(:sha, data)
    end
  end
end

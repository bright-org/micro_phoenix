defmodule Phoenix.WebSocket.SHA1 do
  @moduledoc false
  import Bitwise

  @mask 0xFFFFFFFF
  @initial {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0}

  def hash(message) when is_binary(message) do
    bits = bit_size(message)
    zeroes = rem(448 - rem(bits + 8, 512) + 512, 512)
    padded = <<message::binary, 0x80, 0::size(zeroes), bits::64>>
    {a, b, c, d, e} = chunks(padded, @initial)
    <<a::32, b::32, c::32, d::32, e::32>>
  end

  defp chunks(<<>>, state), do: state

  defp chunks(<<block::binary-size(64), rest::binary>>, state) do
    words = :erlang.list_to_tuple(for <<word::unsigned-big-32 <- block>>, do: word)
    words = expand(words, 16)
    chunks(rest, round(words, 0, state, state))
  end

  defp expand(words, 80), do: words

  defp expand(words, index) do
    value =
      bxor(
        bxor(elem(words, index - 3), elem(words, index - 8)),
        bxor(elem(words, index - 14), elem(words, index - 16))
      )

    expand(:erlang.list_to_tuple(:erlang.tuple_to_list(words) ++ [rotate(value, 1)]), index + 1)
  end

  defp round(_words, 80, {a, b, c, d, e}, {h0, h1, h2, h3, h4}) do
    {mask(a + h0), mask(b + h1), mask(c + h2), mask(d + h3), mask(e + h4)}
  end

  defp round(words, index, {a, b, c, d, e}, initial) do
    {function, constant} =
      cond do
        index < 20 -> {bor(band(b, c), band(bnot(b), d)), 0x5A827999}
        index < 40 -> {bxor(bxor(b, c), d), 0x6ED9EBA1}
        index < 60 -> {bor(bor(band(b, c), band(b, d)), band(c, d)), 0x8F1BBCDC}
        true -> {bxor(bxor(b, c), d), 0xCA62C1D6}
      end

    next = mask(rotate(a, 5) + function + e + constant + elem(words, index))
    round(words, index + 1, {next, a, rotate(b, 30), c, d}, initial)
  end

  defp rotate(value, count), do: mask(bor(value <<< count, value >>> (32 - count)))
  defp mask(value), do: band(value, @mask)
end

defmodule Phoenix.Binary do
  @moduledoc false

  # Minimal binary helpers for AtomVM (no Elixir.String module).

  def split(bin, sep) when is_binary(bin) and is_binary(sep) do
    :binary.split(bin, sep, [:global])
  end

  def split2(bin, sep) when is_binary(bin) and is_binary(sep) do
    :binary.split(bin, sep)
  end

  def split_trim(bin, sep) when is_binary(bin) and is_binary(sep) do
    bin
    |> split(sep)
    |> Enum.reject(&(&1 == ""))
  end

  def upcase_ascii(bin) when is_binary(bin) do
    for <<c <- bin>>, into: <<>> do
      if c >= ?a and c <= ?z, do: <<c - 32>>, else: <<c>>
    end
  end

  def downcase_ascii(bin) when is_binary(bin) do
    for <<c <- bin>>, into: <<>> do
      if c >= ?A and c <= ?Z, do: <<c + 32>>, else: <<c>>
    end
  end

  def starts_with?(bin, prefix)
      when is_binary(bin) and is_binary(prefix) do
    prefix_size = byte_size(prefix)

    byte_size(bin) >= prefix_size and
      binary_part(bin, 0, prefix_size) == prefix
  end

  def parse_integer(bin) when is_binary(bin) do
    parse_integer(bin, 0, false)
  end

  defp parse_integer(<<c, rest::binary>>, acc, _seen?) when c >= ?0 and c <= ?9 do
    parse_integer(rest, acc * 10 + (c - ?0), true)
  end

  defp parse_integer(rest, acc, true), do: {acc, rest}
  defp parse_integer(_rest, _acc, false), do: :error

  def http_method_atom(method) when is_binary(method) do
    case downcase_ascii(method) do
      "get" -> :get
      "post" -> :post
      "put" -> :put
      "patch" -> :patch
      "delete" -> :delete
      "head" -> :head
      "options" -> :options
      other -> :erlang.binary_to_atom(other, :utf8)
    end
  end
end

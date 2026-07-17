defmodule Template do
  def render(_conn, html, assigns \\ %{}) when is_binary(html) do
    {:ok, 200, "text/html", render_template(html, assigns)}
  end

  defp render_template(template, assigns) do
    render_template(template, assigns, <<>>)
  end

  defp render_template(<<>>, _assigns, acc), do: acc

  defp render_template(template, assigns, acc) do
    case :binary.match(template, "<%=") do
      {start, tag_len} ->
        before = binary_part(template, 0, start)
        rest = binary_part(template, start + tag_len, byte_size(template) - start - tag_len)

        case :binary.match(rest, "%>") do
          {var_len, close_len} ->
            var_name = binary_part(rest, 0, var_len) |> trim_ascii()
            after_tag = binary_part(rest, var_len + close_len, byte_size(rest) - var_len - close_len)
            value = lookup_assign(assigns, var_name)
            render_template(after_tag, assigns, acc <> before <> value)

          :nomatch ->
            acc <> template
        end

      :nomatch ->
        acc <> template
    end
  end

  defp trim_ascii(bin) do
    bin |> trim_leading_ascii() |> trim_trailing_ascii()
  end

  defp trim_leading_ascii(<<" ", rest::binary>>), do: trim_leading_ascii(rest)
  defp trim_leading_ascii(<<"\t", rest::binary>>), do: trim_leading_ascii(rest)
  defp trim_leading_ascii(<<"@", rest::binary>>), do: trim_leading_ascii(rest)
  defp trim_leading_ascii(bin), do: bin

  defp trim_trailing_ascii(bin) do
    size = byte_size(bin)

    if size > 0 and :binary.at(bin, size - 1) in [?\s, ?\t] do
      trim_trailing_ascii(binary_part(bin, 0, size - 1))
    else
      bin
    end
  end

  defp lookup_assign(assigns, var_name) do
    atom_key =
      try do
        :erlang.binary_to_existing_atom(var_name, :utf8)
      catch
        :error, :badarg -> nil
      end

    value =
      cond do
        atom_key != nil and Map.has_key?(assigns, atom_key) -> Map.get(assigns, atom_key)
        Map.has_key?(assigns, var_name) -> Map.get(assigns, var_name)
        true -> nil
      end

    case value do
      nil -> ""
      v when is_list(v) -> Enum.join(v, "")
      v when is_binary(v) -> v
      v when is_integer(v) -> integer_to_binary(v)
      v when is_atom(v) -> atom_to_binary(v)
      _ -> ""
    end
  end

  defp integer_to_binary(n) when is_integer(n) do
    if n == 0 do
      "0"
    else
      integer_to_binary(n, <<>>)
    end
  end

  defp integer_to_binary(0, acc), do: acc

  defp integer_to_binary(n, acc) when n > 0 do
    digit = rem(n, 10)
    integer_to_binary(div(n, 10), <<digit + ?0>> <> acc)
  end

  defp atom_to_binary(atom) when is_atom(atom) do
    :erlang.atom_to_binary(atom, :utf8)
  rescue
    _ -> ""
  end
end

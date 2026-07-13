defmodule Template do

  def render(_conn, html, assigns \\ %{}) when is_binary(html) do
    {:ok, 200, "text/html", render_template(html, assigns)}
  end

  defp render_template(template, assigns) do
    render_template(template, assigns, "")
  end

  defp render_template("", _assigns, acc), do: acc

  defp render_template(template, assigns, acc) do
    marker = "<%= @"

    case :binary.match(template, marker) do
      :nomatch ->
        acc <> template

      {start, marker_len} ->
        before_marker = :binary.part(template, 0, start)
        after_marker_pos = start + marker_len
        after_marker = :binary.part(template, after_marker_pos, byte_size(template) - after_marker_pos)

        case :binary.match(after_marker, "%>") do
          :nomatch ->
            acc <> template

          {finish, finish_len} ->
            key =
              after_marker
              |> :binary.part(0, finish)
              |> trim_ascii()

            after_finish_pos = finish + finish_len
            after_finish =
              :binary.part(after_marker, after_finish_pos, byte_size(after_marker) - after_finish_pos)

            render_template(after_finish, assigns, acc <> before_marker <> assign_value(assigns, key))
        end
    end
  end

  defp assign_value(assigns, key) do
    atom_key =
      try do
        :erlang.binary_to_existing_atom(key, :utf8)
      rescue
        ArgumentError -> nil
      catch
        _, _ -> nil
      end

    case find_assign(assigns, atom_key, key) do
      nil -> ""
      v when is_list(v) -> :erlang.iolist_to_binary(v)
      v when is_binary(v) -> v
      _ -> ""
    end
  end

  defp find_assign(assigns, atom_key, key) do
    case find_assign_key(assigns, atom_key) do
      {:ok, value} ->
        value

      :error ->
        case find_assign_key(assigns, key) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  defp find_assign_key(_assigns, nil), do: :error

  defp find_assign_key(assigns, key) do
    case :maps.find(key, assigns) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  catch
    _, _ -> :error
  end

  defp trim_ascii(value) do
    value
    |> trim_ascii_left()
    |> trim_ascii_right()
  end

  defp trim_ascii_left(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r] do
    trim_ascii_left(rest)
  end

  defp trim_ascii_left(value), do: value

  defp trim_ascii_right(value) when byte_size(value) > 0 do
    last_pos = byte_size(value) - 1

    case :binary.at(value, last_pos) do
      c when c in [?\s, ?\t, ?\n, ?\r] ->
        value
        |> :binary.part(0, last_pos)
        |> trim_ascii_right()

      _ ->
        value
    end
  end

  defp trim_ascii_right(value), do: value
end

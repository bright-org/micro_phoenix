defmodule Phoenix.VerifiedRoutes do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: Macro.escape(opts, unquote: true)] do
      import Phoenix.VerifiedRoutes, only: [sigil_p: 2]

      Module.register_attribute(__MODULE__, :endpoint, persist: false)
      Module.register_attribute(__MODULE__, :router, persist: false)
      Module.register_attribute(__MODULE__, :statics, persist: false)

      @endpoint Keyword.fetch!(opts, :endpoint)
      @router Keyword.fetch!(opts, :router)
      @statics Keyword.get(opts, :statics, [])
    end
  end

  defmacro sigil_p({:<<>>, _meta, segments}, []) do
    {path_segments, query_segments} = split_segments(segments)
    path_ast = build_path_ast(path_segments)

    if query_segments == [] do
      path_ast
    else
      quote do
        path = unquote(path_ast)
        query = unquote(build_query_ast(query_segments))

        if query == "" do
          path
        else
          path <> "?" <> query
        end
      end
    end
  end

  defmacro sigil_p(_route, extra) do
    raise ArgumentError, "~p does not support modifiers after closing, got: #{inspect(extra)}"
  end

  def __encode_segment__(data) do
    data
    |> Phoenix.Param.to_param()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp split_segments(segments) do
    case segments do
      ["/" <> _ | _] ->
        split_segments(segments, [], [])

      _ ->
        raise ArgumentError, "paths must begin with /, got: #{inspect(segments)}"
    end
  end

  defp split_segments([], path_acc, query_acc), do: {Enum.reverse(path_acc), Enum.reverse(query_acc)}

  defp split_segments(["?" <> query | rest], path_acc, _query_acc) do
    split_segments(rest, path_acc, [query])
  end

  defp split_segments([segment | rest], path_acc, query_acc) when is_binary(segment) do
    case String.split(segment, "?", parts: 2) do
      [path_part, query_part] ->
        split_segments(rest, [path_part | path_acc], [query_part | query_acc])

      [path_part] ->
        split_segments(rest, [path_part | path_acc], query_acc)
    end
  end

  defp split_segments([dynamic | rest], path_acc, query_acc) do
    split_segments(rest, [dynamic | path_acc], query_acc)
  end

  defp build_path_ast(segments) do
    segments
    |> Enum.map(&segment_ast/1)
    |> concat_ast()
  end

  defp build_query_ast(segments) do
    segments
    |> Enum.map(&query_segment_ast/1)
    |> concat_ast()
  end

  defp segment_ast(segment) when is_binary(segment), do: segment

  defp segment_ast({:"::", _, [{{:., _, [Kernel, :to_string]}, _, [dynamic]}, _]}) do
    quote do: Phoenix.VerifiedRoutes.__encode_segment__(unquote(dynamic))
  end

  defp segment_ast(other) do
    raise ArgumentError, "invalid ~p path segment: #{Macro.to_string(other)}"
  end

  defp query_segment_ast(segment) when is_binary(segment), do: segment

  defp query_segment_ast({:"::", _, [{{:., _, [Kernel, :to_string]}, _, [dynamic]}, _]}) do
    quote do: Phoenix.VerifiedRoutes.__encode_segment__(unquote(dynamic))
  end

  defp query_segment_ast(other) do
    raise ArgumentError, "invalid ~p query segment: #{Macro.to_string(other)}"
  end

  defp concat_ast([]), do: ""
  defp concat_ast([segment]), do: segment

  defp concat_ast(segments) do
    Enum.reduce(segments, fn segment, acc ->
      quote do: unquote(acc) <> unquote(segment)
    end)
  end
end

defmodule Phoenix.Param do
  @moduledoc false
  defdelegate to_param(data), to: MicroPhoenix.Param
end

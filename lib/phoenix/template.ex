defmodule Phoenix.Template do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      import Phoenix.Template, only: [embed_templates: 1, embed_templates: 2]
      @phoenix_template_format Keyword.get(unquote(opts), :format, "heex")
    end
  end

  defmacro embed_templates(pattern, _opts \\ []) do
    caller_file = __CALLER__.file
    root = Path.dirname(caller_file)
    pattern = Path.join(root, pattern)
    files = Path.wildcard(pattern)

    definitions =
      for file <- files do
        name =
          file
          |> Path.basename()
          |> Path.rootname(".heex")
          |> Path.rootname(".html")
          |> String.to_atom()

        compiled = compile_heex(file)

        quote do
          def unquote(name)(assigns) do
            var!(assigns) = Map.new(assigns)
            unquote(compiled)
          end
        end
      end

    quote do
      unquote_splicing(definitions)
    end
  end

  def compile_heex(path) when is_binary(path) do
    path
    |> File.read!()
    |> compile_heex_source(path)
  end

  def compile_heex_source(source, file \\ "nofile") when is_binary(source) do
    source
    |> heex_to_eex()
    |> EEx.compile_string(engine: Phoenix.HTML.Engine, line: 1, file: file)
  end

  def heex_to_eex(source) when is_binary(source) do
    {source, scripts} = extract_scripts(source)

    converted =
      source
      |> drop_attribute_spreads()
      |> convert_self_closing_components()
      |> convert_paired_components()
      |> convert_control_flow_tags()
      |> convert_attr_expressions()
      |> protect_eex()
      |> convert_body_interpolations()
      |> restore_eex()
      |> soft_assigns()

    restore_scripts(converted, scripts)
  end

  # Use Map.get so missing assigns don't crash templates during gradual compatibility.
  defp soft_assigns(source) do
    Regex.replace(~r/@([a-zA-Z_][\w]*)/, source, "Map.get(var!(assigns), :\\1)")
  end

  defp protect_eex(source) do
    Regex.replace(~r/<%.*?%>/s, source, fn chunk ->
      "<!--EEX:#{Base.encode64(chunk)}-->"
    end)
  end

  defp restore_eex(source) do
    Regex.replace(~r/<!--EEX:([A-Za-z0-9+\/=]+)-->/, source, fn _, encoded ->
      Base.decode64!(encoded)
    end)
  end

  # Convert HEEx attribute spreads like `{@rest}` inside tags only.
  # Require that the next `>` appears before any `<`, so body `{@inner_content}` is untouched.
  defp drop_attribute_spreads(source) do
    Regex.replace(~r/\s\{@([a-zA-Z_][\w]*)\}(?=[^<]*?>)/, source, fn _, name ->
      " <%= Phoenix.Template.__attrs__(Map.get(var!(assigns), :#{name})) %>"
    end)
  end

  def __attrs__(nil), do: ""
  def __attrs__(false), do: ""

  def __attrs__(attrs) when is_map(attrs) or is_list(attrs) do
    attrs
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, false} -> true
      {:inner_block, _} -> true
      {"inner_block", _} -> true
      {:rest, _} -> true
      {"rest", _} -> true
      {k, _} when k in [:actions, :action, :col, :item, :subtitle] -> true
      _ -> false
    end)
    |> Enum.map(fn {key, value} ->
      # Avoid String.replace/3 for AtomVM (no Elixir.String module).
      key = key |> to_string() |> underscore_to_dash()

      cond do
        value == true ->
          key

        is_binary(value) or is_atom(value) or is_number(value) ->
          escaped =
            case Phoenix.HTML.html_escape(to_string(value)) do
              {:safe, data} -> IO.iodata_to_binary(data)
              other -> to_string(other)
            end

          ~s(#{key}="#{escaped}")

        true ->
          ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  def __attrs__(_), do: ""

  defp underscore_to_dash(bin) when is_binary(bin) do
    for <<c <- bin>>, into: <<>> do
      if c == ?_, do: <<?->>, else: <<c>>
    end
  end

  defp convert_self_closing_components(source) do
    Regex.replace(~r/<((?:Layouts\.)[\w]+|\.[\w]+)(\s[^>]*?|\s*)\/>/s, source, fn _full, tag, attrs ->
      fun = component_fun(tag)
      {for_expr, if_expr, _let_expr, rest_attrs} = split_special_attrs(attrs)
      call = wrap_component_call(fun, rest_attrs, nil)

      cond do
        for_expr && if_expr ->
          "<%= for #{for_expr} do %><%= if #{if_expr} do %><%= #{call} %><% end %><% end %>"

        for_expr ->
          "<%= for #{for_expr} do %><%= #{call} %><% end %>"

        if_expr ->
          "<%= if #{if_expr} do %><%= #{call} %><% end %>"

        true ->
          "<%= #{call} %>"
      end
    end)
  end

  defp convert_paired_components(source) do
    Regex.replace(
      ~r/<((?:Layouts\.)[\w]+|\.[\w]+)([^>]*)>(.*?)<\/\1>/s,
      source,
      fn _, name, attrs, inner ->
        fun = component_fun(name)
        # Convert nested components first so they own their <:slots>
        inner = convert_paired_components(inner)
        {slots, default_inner} = extract_named_slots(inner)

        case split_special_attrs(attrs) do
          {nil, nil, let_expr, rest_attrs} ->
            wrap_component(fun, rest_attrs, default_inner, slots, let_expr)

          {nil, if_expr, let_expr, rest_attrs} ->
            "<%= if #{if_expr} do %>#{wrap_component(fun, rest_attrs, default_inner, slots, let_expr)}<% end %>"

          {for_expr, nil, let_expr, rest_attrs} ->
            "<%= for #{for_expr} do %>#{wrap_component(fun, rest_attrs, default_inner, slots, let_expr)}<% end %>"

          {for_expr, if_expr, let_expr, rest_attrs} ->
            "<%= for #{for_expr} do %><%= if #{if_expr} do %>#{wrap_component(fun, rest_attrs, default_inner, slots, let_expr)}<% end %><% end %>"
        end
      end
    )
  end

  defp component_fun(tag) do
    cond do
      String.starts_with?(tag, "Layouts.") -> tag
      String.starts_with?(tag, ".") -> String.trim_leading(tag, ".")
      true -> tag
    end
  end

  defp wrap_component(fun, attrs, inner, slots, let_expr) do
    "<%= #{wrap_component_call(fun, attrs, {inner, slots, let_expr})} %>"
  end

  defp wrap_component_call(fun, attrs, nil) do
    assign_map = build_assigns(attrs, nil, [], nil)
    "#{fun}(%{#{assign_map}})"
  end

  defp wrap_component_call(fun, attrs, {inner, slots, let_expr}) do
    assign_map = build_assigns(attrs, inner, slots, let_expr)
    "#{fun}(%{#{assign_map}})"
  end

  defp build_assigns(attrs, inner, slots, let_expr) do
    attrs_map = parse_attrs(attrs)
    attr_keys =
      attrs_map
      |> String.split(",", trim: true)
      |> Enum.map(fn part ->
        part |> String.split(":", parts: 2) |> hd() |> String.trim()
      end)
      |> MapSet.new()

    slot_assigns = build_slot_assigns(slots || [])
    provided_slots = MapSet.new(Enum.map(slots || [], fn {name, _, _} -> name end))

    defaults =
      ~w(actions action col item subtitle)
      |> Enum.reject(&(MapSet.member?(provided_slots, &1) or MapSet.member?(attr_keys, &1)))
      |> Enum.map(&"#{&1}: []")

    # Common attr defaults expected by phx.gen / core_components when attr/3 is a no-op.
    # Do NOT default keys that components set via assign_new/3 (e.g. :name, :value).
    assign_defaults =
      [
        "id: nil",
        "title: nil",
        "class: nil",
        "label: nil",
        "errors: []",
        "checked: nil",
        "prompt: nil",
        "options: nil",
        "multiple: false",
        "error_class: nil",
        "variant: nil"
      ]
      |> Enum.reject(fn default ->
        key = default |> String.split(":", parts: 2) |> hd() |> String.trim()
        MapSet.member?(attr_keys, key) or MapSet.member?(provided_slots, key)
      end)

    let_arg = let_expr || "_"

    inner_assign =
      case inner do
        nil -> nil
        _ -> "inner_block: fn #{let_arg} -> %>#{inner}<% end"
      end

    rest_assign =
      if attrs_map == "" do
        "rest: %{}"
      else
        "rest: %{#{attrs_map}}"
      end

    # defaults first, then attrs/slots so real attributes win on key clashes
    [
      Enum.join(defaults, ", "),
      Enum.join(assign_defaults, ", "),
      Enum.join(slot_assigns, ", "),
      attrs_map,
      rest_assign,
      inner_assign
    ]
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join(", ")
  end

  defp build_slot_assigns(slots) do
    slots
    |> Enum.group_by(fn {name, _, _} -> name end)
    |> Enum.map(fn {name, entries} ->
      rendered =
        entries
        |> Enum.map(fn {_, slot_attrs, content} ->
          {_for_expr, _if_expr, let_expr, rest_attrs} = split_special_attrs(slot_attrs)
          attrs_map = parse_attrs(rest_attrs)
          let_arg = let_expr || "_"

          slot_body =
            if attrs_map == "" do
              "inner_block: fn #{let_arg} -> %>#{content}<% end"
            else
              "#{attrs_map}, inner_block: fn #{let_arg} -> %>#{content}<% end"
            end

          "%{#{slot_body}}"
        end)
        |> Enum.join(", ")

      "#{name}: [#{rendered}]"
    end)
  end

  defp extract_named_slots(inner) do
    matches = Regex.scan(~r/<:([\w]+)([^>]*)>(.*?)<\/:\1>/s, inner)

    reduced =
      Enum.reduce(matches, inner, fn [full | _], acc ->
        String.replace(acc, full, "", global: false)
      end)

    slots =
      Enum.map(matches, fn [_full, name, attrs, content] ->
        {name, attrs, content}
      end)

    {slots, String.trim(reduced)}
  end

  defp convert_control_flow_tags(source) do
    source
    |> convert_for_tags()
    |> convert_if_tags()
  end

  defp convert_for_tags(source) do
    replace_special_open_close(source, "for")
  end

  defp convert_if_tags(source) do
    replace_special_open_close(source, "if")
  end

  defp replace_special_open_close(source, kind) do
    open_re = ~r/<([a-zA-Z][\w:-]*)([^>]*?)\s:#{kind}=\{/

    case Regex.run(open_re, source, return: :index) do
      nil ->
        source

      [{start, _} | _] ->
        prefix = binary_part(source, 0, start)
        from_tag = binary_part(source, start, byte_size(source) - start)

        case take_special_tag(from_tag, kind) do
          {:ok, tag, attrs, expr, inner, rest} ->
            attrs = strip_special_attrs(attrs)
            inner = replace_special_open_close(inner, kind)
            kw = if(kind == "for", do: "for", else: "if")

            replaced =
              "<%= #{kw} #{expr} do %><#{tag}#{attrs}>#{inner}</#{tag}><% end %>"

            prefix <> replaced <> replace_special_open_close(rest, kind)

          :error ->
            source
        end
    end
  end

  defp take_special_tag(<<"<", rest::binary>>, kind) do
    case Regex.run(~r/^([a-zA-Z][\w:-]*)/, rest) do
      [_, tag] ->
        after_tag = binary_part(rest, byte_size(tag), byte_size(rest) - byte_size(tag))

        case extract_special(after_tag, kind) do
          {nil, _} ->
            :error

          {expr, attrs_without_special} ->
            case Regex.run(~r/^([^>]*)>/, attrs_without_special, return: :index) do
              [{0, full_len}, {a0, alen}] ->
                attrs = binary_part(attrs_without_special, a0, alen)
                after_open = binary_part(attrs_without_special, full_len, byte_size(attrs_without_special) - full_len)

                case take_matched_tag(after_open, tag) do
                  {inner, rest} -> {:ok, tag, attrs, expr, inner, rest}
                  :error -> :error
                end

              nil ->
                :error
            end
        end

      nil ->
        :error
    end
  end

  defp take_special_tag(_, _), do: :error

  defp take_matched_tag(source, tag), do: take_matched_tag(source, tag, 1, "")

  defp take_matched_tag("", _tag, _depth, _acc), do: :error

  defp take_matched_tag(source, tag, depth, acc) do
    open = "<" <> tag
    close = "</" <> tag <> ">"

    cond do
      String.starts_with?(source, close) ->
        rest = binary_part(source, byte_size(close), byte_size(source) - byte_size(close))

        if depth == 1 do
          {acc, rest}
        else
          take_matched_tag(rest, tag, depth - 1, acc <> close)
        end

      String.starts_with?(source, open) and next_is_tag_boundary(source, byte_size(open)) ->
        case Regex.run(~r/^#{Regex.escape(open)}([^>]*)>/, source) do
          [chunk, attrs] ->
            rest = binary_part(source, byte_size(chunk), byte_size(source) - byte_size(chunk))
            self_closing? = String.ends_with?(String.trim(attrs), "/")
            new_depth = if self_closing?, do: depth, else: depth + 1
            take_matched_tag(rest, tag, new_depth, acc <> chunk)

          nil ->
            <<c::utf8, rest::binary>> = source
            take_matched_tag(rest, tag, depth, acc <> <<c::utf8>>)
        end

      true ->
        <<c::utf8, rest::binary>> = source
        take_matched_tag(rest, tag, depth, acc <> <<c::utf8>>)
    end
  end

  defp next_is_tag_boundary(source, open_len) do
    case binary_part(source, open_len, 1) do
      " " -> true
      ">" -> true
      "/" -> true
      "\n" -> true
      "\t" -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp convert_attr_expressions(source) do
    replace_balanced(source, ~r/([\w\-:]+)=\{/, fn key, expr, rest ->
      key = String.trim_trailing(key, "=")
      {~s(#{key}="<%= #{attr_expr(expr)} %>"), rest}
    end)
  end

  defp convert_body_interpolations(source) do
    replace_balanced(source, ~r/\{/, fn "", expr, rest ->
      if String.trim(expr) == "" do
        {"{}", rest}
      else
        {"<%= #{String.trim(expr)} %>", rest}
      end
    end)
  end

  defp replace_balanced(source, open_re, fun) do
    case Regex.run(open_re, source, return: :index) do
      nil ->
        source

      [{start, len} | _] ->
        prefix = binary_part(source, 0, start)
        after_open = binary_part(source, start + len, byte_size(source) - start - len)
        key = binary_part(source, start, len) |> String.trim_trailing("{")

        case take_balanced(after_open) do
          {expr, rest} ->
            {replacement, rest2} = fun.(key, expr, rest)
            prefix <> replacement <> replace_balanced(rest2, open_re, fun)

          :error ->
            source
        end
    end
  end

  defp take_balanced(<<"{", rest::binary>>), do: take_balanced(rest, 1, "")
  defp take_balanced(rest), do: take_balanced(rest, 1, "")

  defp take_balanced("", _depth, _acc), do: :error

  defp take_balanced(<<"{", rest::binary>>, depth, acc) do
    take_balanced(rest, depth + 1, acc <> "{")
  end

  defp take_balanced(<<"}", rest::binary>>, 1, acc), do: {acc, rest}

  defp take_balanced(<<"}", rest::binary>>, depth, acc) do
    take_balanced(rest, depth - 1, acc <> "}")
  end

  defp take_balanced(<<"\"", rest::binary>>, depth, acc) do
    {str, rest} = take_string(rest, "\"")
    take_balanced(rest, depth, acc <> "\"" <> str <> "\"")
  end

  defp take_balanced(<<"'", rest::binary>>, depth, acc) do
    {str, rest} = take_string(rest, "'")
    take_balanced(rest, depth, acc <> "'" <> str <> "'")
  end

  defp take_balanced(<<c::utf8, rest::binary>>, depth, acc) do
    take_balanced(rest, depth, acc <> <<c::utf8>>)
  end

  defp take_string(rest, quote_char), do: take_string(rest, quote_char, "")

  defp take_string(<<>>, _q, acc), do: {acc, ""}

  defp take_string(<<"\\", c::utf8, rest::binary>>, q, acc) do
    take_string(rest, q, acc <> "\\" <> <<c::utf8>>)
  end

  defp take_string(<<c::utf8, rest::binary>>, q, acc) do
    if <<c::utf8>> == q do
      {acc, rest}
    else
      take_string(rest, q, acc <> <<c::utf8>>)
    end
  end

  defp attr_expr(expr) do
    trimmed = String.trim(expr)

    if String.starts_with?(trimmed, "[") do
      "Phoenix.Template.__class_list__(#{trimmed})"
    else
      trimmed
    end
  end

  def __class_list__(list) when is_list(list) do
    list
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == false))
    |> Enum.join(" ")
  end

  def __class_list__(other), do: to_string(other)

  defp split_special_attrs(attrs) do
    {for_expr, attrs} = extract_special(attrs, "for")
    {if_expr, attrs} = extract_special(attrs, "if")
    {let_expr, attrs} = extract_special(attrs, "let")
    {for_expr, if_expr, let_expr, attrs}
  end

  defp extract_special(attrs, kind) do
    case Regex.run(~r/(?:^|\s):#{kind}=\{/, attrs, return: :index) do
      [{start, len}] ->
        # include the leading whitespace in the match start removal, keep preceding text
        before = binary_part(attrs, 0, start)
        after_open = binary_part(attrs, start + len, byte_size(attrs) - start - len)

        case take_balanced(after_open) do
          {expr, rest} -> {expr, before <> rest}
          :error -> {nil, attrs}
        end

      nil ->
        {nil, attrs}
    end
  end

  defp strip_special_attrs(attrs) do
    {_, _, _, attrs} = split_special_attrs(attrs)
    attrs
  end

  defp parse_attrs(attrs) do
    attrs
    |> String.trim()
    |> do_parse_attrs([])
    |> Enum.reverse()
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  defp do_parse_attrs("", acc), do: acc

  defp do_parse_attrs(rest, acc) do
    rest = String.trim_leading(rest)

    case Regex.run(~r/^([:\w\-]+)/, rest) do
      [match, key] ->
        rest = binary_part(rest, byte_size(match), byte_size(rest) - byte_size(match))
        rest = String.trim_leading(rest)

        cond do
          String.starts_with?(key, ":") ->
            # drop :for/:if leftover fragments if any
            do_parse_attrs(drop_optional_value(rest), acc)

          String.starts_with?(rest, "=") ->
            rest = binary_part(rest, 1, byte_size(rest) - 1)

            case next_attr_value(String.trim_leading(rest)) do
              {val, rest} -> do_parse_attrs(rest, [{normalize_key(key), val} | acc])
              :error -> acc
            end

          true ->
            do_parse_attrs(rest, [{normalize_key(key), "true"} | acc])
        end

      nil ->
        acc
    end
  end

  defp drop_optional_value(<<"=", rest::binary>>) do
    case next_attr_value(String.trim_leading(rest)) do
      {_val, rest} -> rest
      :error -> rest
    end
  end

  defp drop_optional_value(rest), do: rest

  defp next_attr_value(<<"\"", rest::binary>>) do
    {str, rest} = take_string(rest, "\"")
    {inspect(str), rest}
  end

  defp next_attr_value(<<"'", rest::binary>>) do
    {str, rest} = take_string(rest, "'")
    {inspect(str), rest}
  end

  defp next_attr_value(<<"{", rest::binary>>) do
    case take_balanced(rest) do
      {expr, rest} -> {expr, rest}
      :error -> :error
    end
  end

  defp next_attr_value(rest) do
    case Regex.run(~r/^([^\s>\/]+)/, rest) do
      [match, val] -> {val, binary_part(rest, byte_size(match), byte_size(rest) - byte_size(match))}
      nil -> :error
    end
  end

  defp normalize_key(key), do: key |> String.replace("-", "_")

  defp extract_scripts(source) do
    scripts = Regex.scan(~r/<script\b[^>]*>.*?<\/script>/ms, source, capture: :all)

    reduced =
      Enum.reduce(Enum.with_index(scripts), source, fn {[script], idx}, acc ->
        String.replace(acc, script, "<!--SCRIPT#{idx}-->", global: false)
      end)

    script_map =
      scripts
      |> Enum.with_index()
      |> Map.new(fn {[script], idx} ->
        {"<!--SCRIPT#{idx}-->", convert_script_attrs(script)}
      end)

    {reduced, script_map}
  end

  defp convert_script_attrs(script) do
    case Regex.run(~r/src=\{(~p"[^"]*")\}/, script) do
      [full, expr] -> String.replace(script, full, "src=\"<%= #{expr} %>\"")
      _ -> script
    end
  end

  defp restore_scripts(source, scripts) do
    Enum.reduce(scripts, source, fn {placeholder, script}, acc ->
      String.replace(acc, placeholder, script)
    end)
  end
end

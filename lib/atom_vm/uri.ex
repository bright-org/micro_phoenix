defmodule AtomVM.URI do
  @moduledoc """
  URI operations implemented without the standard Elixir `URI` module.
  """

  defstruct scheme: nil,
            authority: nil,
            userinfo: nil,
            host: nil,
            port: nil,
            path: nil,
            query: nil,
            fragment: nil

  @type t :: %__MODULE__{
          scheme: binary() | nil,
          authority: binary() | nil,
          userinfo: binary() | nil,
          host: binary() | nil,
          port: non_neg_integer() | nil,
          path: binary() | nil,
          query: binary() | nil,
          fragment: binary() | nil
        }

  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{}, %__MODULE__{scheme: scheme} = relative)
      when not is_nil(scheme),
      do: %{
        relative
        | path: normalize_path(relative.path),
          port: relative.port || default_port(scheme)
      }

  def merge(%__MODULE__{} = base, %__MODULE__{host: host} = relative)
      when not is_nil(host),
      do: %{relative | scheme: base.scheme, path: normalize_path(relative.path)}

  def merge(%__MODULE__{} = base, %__MODULE__{path: nil} = relative) do
    %{base | query: relative.query || base.query, fragment: relative.fragment}
  end

  def merge(%__MODULE__{} = base, %__MODULE__{path: "/" <> _} = relative) do
    %{
      base
      | path: normalize_path(relative.path),
        query: relative.query,
        fragment: relative.fragment
    }
  end

  def merge(%__MODULE__{} = base, %__MODULE__{} = relative) do
    parent =
      case base.path do
        nil ->
          "/"

        path ->
          parts = :binary.split(path, "/", [:global])
          :erlang.iolist_to_binary(join_parts(drop_last(parts), "/")) <> "/"
      end

    %{
      base
      | path: normalize_path(parent <> relative.path),
        query: relative.query,
        fragment: relative.fragment
    }
  end

  defp drop_last([_]), do: []
  defp drop_last([part | rest]), do: [part | drop_last(rest)]

  defp normalize_path(nil), do: nil

  defp normalize_path(path) do
    parts = :binary.split(path, "/", [:global])
    normalized = normalize_parts(parts, [])
    :erlang.iolist_to_binary(join_parts(reverse(normalized, []), "/"))
  end

  defp normalize_parts([], acc), do: acc
  defp normalize_parts(["."], acc), do: ["" | acc]
  defp normalize_parts([".."], [""]), do: [""]
  defp normalize_parts([".."], ["", previous | acc]), do: ["", previous | acc]
  defp normalize_parts([".."], [_previous | acc]), do: ["" | acc]
  defp normalize_parts([".."], []), do: [""]
  defp normalize_parts(["." | rest], acc), do: normalize_parts(rest, acc)

  defp normalize_parts([".." | rest], ["", previous | acc]),
    do: normalize_parts(rest, [previous | acc])

  defp normalize_parts([".." | rest], ["" | _] = acc), do: normalize_parts(rest, acc)
  defp normalize_parts([".." | rest], [_previous | acc]), do: normalize_parts(rest, acc)
  defp normalize_parts([".." | rest], acc), do: normalize_parts(rest, acc)
  defp normalize_parts([part | rest], acc), do: normalize_parts(rest, [part | acc])

  defp join_parts([], _separator), do: []
  defp join_parts([part], _separator), do: [part]
  defp join_parts([part | rest], separator), do: [part, separator | join_parts(rest, separator)]

  @spec new!(binary() | t()) :: t()
  def new!(%__MODULE__{} = uri), do: uri

  def new!(input) when is_binary(input) do
    if invalid_new_uri?(input),
      do: raise(AtomVM.URI.Error, action: :parse, reason: :invalid_uri, part: ":")

    %{parse(input) | authority: nil}
  end

  defp invalid_new_uri?(input) do
    {without_fragment, _fragment} = split_once(input, "#")
    {without_query, _query} = split_once(without_fragment, "?")
    {_, rest} = split_scheme(without_query)
    {authority, _} = split_authority(rest)
    invalid_ascii?(input) or invalid_authority?(authority)
  end

  defp invalid_ascii?(<<>>), do: false
  defp invalid_ascii?(<<byte, _::binary>>) when byte <= 32 or byte >= 127, do: true
  defp invalid_ascii?(<<_, rest::binary>>), do: invalid_ascii?(rest)

  defp invalid_authority?(nil), do: false

  defp invalid_authority?(authority) do
    {host_port, repeated_at?} =
      case split_once(authority, "@") do
        {_, nil} -> {authority, false}
        {_, rest} -> {rest, :binary.match(rest, "@") != :nomatch}
      end

    invalid_bracket? =
      case host_port do
        "[" <> rest ->
          case split_once(rest, "]") do
            {host, ""} -> not valid_ipv6?(host)
            {host, ":" <> _} -> not valid_ipv6?(host)
            _ -> true
          end

        _ ->
          false
      end

    {_, port_text} = split_host_port(host_port)

    repeated_at? or invalid_bracket? or :binary.match(host_port, "\\") != :nomatch or
      (port_text != nil and port_text != "" and digits(port_text, 0) == :error)
  end

  defp valid_ipv6?(host) do
    case split_once(host, "::") do
      {_, nil} ->
        case ipv6_groups(host) do
          {:ok, 8} -> true
          _ -> false
        end

      {left, right} ->
        if :binary.match(right, "::") != :nomatch do
          false
        else
          with {:ok, left_count} <- ipv6_groups(left),
               {:ok, right_count} <- ipv6_groups(right) do
            left_count + right_count < 8
          else
            _ -> false
          end
        end
    end
  end

  defp ipv6_groups(""), do: {:ok, 0}
  defp ipv6_groups(part), do: ipv6_groups(:binary.split(part, ":", [:global]), 0)
  defp ipv6_groups([], count), do: {:ok, count}

  defp ipv6_groups([group | rest], count) do
    cond do
      valid_hex_group?(group) -> ipv6_groups(rest, count + 1)
      rest == [] and valid_ipv4?(group) -> {:ok, count + 2}
      true -> :error
    end
  end

  defp valid_hex_group?(group) when byte_size(group) in 1..4,
    do: valid_hex_bytes?(group)

  defp valid_hex_group?(_), do: false
  defp valid_hex_bytes?(<<>>), do: true

  defp valid_hex_bytes?(<<byte, rest::binary>>)
       when byte in ?0..?9 or byte in ?a..?f or byte in ?A..?F,
       do: valid_hex_bytes?(rest)

  defp valid_hex_bytes?(_), do: false

  defp valid_ipv4?(group) do
    case :binary.split(group, ".", [:global]) do
      [a, b, c, d] ->
        ipv4_octet?(a) and ipv4_octet?(b) and ipv4_octet?(c) and ipv4_octet?(d)

      _ ->
        false
    end
  end

  defp ipv4_octet?(<<>>), do: false
  defp ipv4_octet?(<<"0", _, _::binary>>), do: false

  defp ipv4_octet?(octet) when byte_size(octet) <= 3 do
    case digits(octet, 0) do
      {:ok, value} -> value <= 255
      _ -> false
    end
  end

  defp ipv4_octet?(_), do: false

  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{} = uri) do
    :erlang.iolist_to_binary([
      if(uri.scheme, do: [uri.scheme, ":"], else: []),
      format_host(uri),
      uri.path || "",
      if(is_nil(uri.query), do: [], else: ["?", uri.query]),
      if(is_nil(uri.fragment), do: [], else: ["#", uri.fragment])
    ])
  end

  defp format_host(%{host: nil}), do: []

  defp format_host(%{host: host, userinfo: userinfo, port: port, scheme: scheme}) do
    bracketed_host =
      if :binary.match(host, ":") == :nomatch, do: host, else: ["[", host, "]"]

    [
      "//",
      if(is_nil(userinfo), do: [], else: [userinfo, "@"]),
      bracketed_host,
      if(is_nil(port) or port == default_port(scheme),
        do: [],
        else: [":", :erlang.integer_to_binary(port)]
      )
    ]
  end

  @spec parse(binary() | t()) :: t()
  def parse(%__MODULE__{} = uri), do: uri

  def parse(input) when is_binary(input) do
    {without_fragment, fragment} = split_once(input, "#")
    {without_query, query} = split_once(without_fragment, "?")
    {scheme, rest} = split_scheme(without_query)
    {authority, path} = split_authority(rest)
    {userinfo, host, port} = parse_authority(authority, scheme)

    %__MODULE__{
      scheme: scheme,
      authority: authority,
      userinfo: userinfo,
      host: host,
      port: port,
      path: empty_to_nil(path),
      query: query,
      fragment: fragment
    }
  end

  defp split_once(input, separator) do
    case :binary.split(input, separator) do
      [before, tail] -> {before, tail}
      [before] -> {before, nil}
    end
  end

  defp split_scheme(input) do
    case split_once(input, ":") do
      {candidate, rest} when not is_nil(rest) ->
        if valid_scheme?(candidate), do: {downcase_ascii(candidate, []), rest}, else: {nil, input}

      _ ->
        {nil, input}
    end
  end

  defp downcase_ascii(<<>>, acc), do: :erlang.iolist_to_binary(reverse(acc, []))

  defp downcase_ascii(<<char, rest::binary>>, acc) when char in ?A..?Z,
    do: downcase_ascii(rest, [<<char + 32>> | acc])

  defp downcase_ascii(<<char, rest::binary>>, acc),
    do: downcase_ascii(rest, [<<char>> | acc])

  defp valid_scheme?(<<first, rest::binary>>) when first in ?a..?z or first in ?A..?Z,
    do: valid_scheme_tail?(rest)

  defp valid_scheme?(_), do: false

  defp valid_scheme_tail?(<<>>), do: true

  defp valid_scheme_tail?(<<char, rest::binary>>)
       when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?+, ?-, ?.] do
    valid_scheme_tail?(rest)
  end

  defp valid_scheme_tail?(_), do: false

  defp split_authority("//" <> rest) do
    case split_once(rest, "/") do
      {authority, nil} -> {authority, nil}
      {authority, path} -> {authority, "/" <> path}
    end
  end

  defp split_authority(path), do: {nil, path}

  defp parse_authority(nil, _scheme), do: {nil, nil, nil}

  defp parse_authority(authority, scheme) do
    {userinfo, host_port} =
      case reverse(:binary.split(authority, "@", [:global]), []) do
        [host_port] ->
          {nil, host_port}

        [host_port | userinfo_parts] ->
          {:erlang.iolist_to_binary(join_parts(reverse(userinfo_parts, []), "@")), host_port}
      end

    {host, port_text} = split_host_port(host_port)
    port = if port_text == nil, do: default_port(scheme), else: parse_port(port_text, scheme)
    {userinfo, host, port}
  end

  defp split_host_port("[" <> rest) do
    case split_once(rest, "]") do
      {host, ":" <> port} -> {host, port}
      {host, suffix} when not is_nil(suffix) -> {host, nil}
      _ -> {"", nil}
    end
  end

  defp split_host_port(host_port) do
    case split_once(host_port, ":") do
      {host, nil} -> {host, nil}
      {host, port} -> {host, port}
    end
  end

  defp parse_port(<<>>, scheme), do: default_port(scheme)

  defp parse_port(port, scheme) do
    case digit_prefix(port, 0, false) do
      {:ok, value} -> value
      :error -> default_port(scheme)
    end
  end

  defp digit_prefix(<<digit, rest::binary>>, value, _seen) when digit in ?0..?9,
    do: digit_prefix(rest, value * 10 + digit - ?0, true)

  defp digit_prefix(_, value, true), do: {:ok, value}
  defp digit_prefix(_, _, false), do: :error

  defp digits(<<>>, value), do: {:ok, value}

  defp digits(<<digit, rest::binary>>, value) when digit in ?0..?9,
    do: digits(rest, value * 10 + digit - ?0)

  defp digits(_, _), do: :error

  @spec default_port(binary() | nil) :: non_neg_integer() | nil
  def default_port("http"), do: 80
  def default_port("https"), do: 443
  def default_port("ftp"), do: 21
  def default_port("sftp"), do: 22
  def default_port("ws"), do: 80
  def default_port("wss"), do: 443
  def default_port(_), do: nil

  @spec char_unreserved?(non_neg_integer()) :: boolean()
  def char_unreserved?(char)
      when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or
             char in [?-, ?., ?_, ?~],
      do: true

  def char_unreserved?(_), do: false

  @spec encode(binary(), (non_neg_integer() -> boolean())) :: binary()
  def encode(binary, predicate) when is_binary(binary) and is_function(predicate, 1),
    do: encode_bytes(binary, predicate, [])

  defp encode_bytes(<<>>, _predicate, acc), do: :erlang.iolist_to_binary(reverse(acc, []))

  defp encode_bytes(<<byte, rest::binary>>, predicate, acc) do
    if predicate.(byte) do
      encode_bytes(rest, predicate, [<<byte>> | acc])
    else
      encode_bytes(rest, predicate, [percent(byte) | acc])
    end
  end

  @spec encode_www_form(binary()) :: binary()
  def encode_www_form(binary) when is_binary(binary), do: encode_form_bytes(binary, [])

  defp encode_form_bytes(<<>>, acc), do: :erlang.iolist_to_binary(reverse(acc, []))
  defp encode_form_bytes(<<?\s, rest::binary>>, acc), do: encode_form_bytes(rest, ["+" | acc])

  defp encode_form_bytes(<<byte, rest::binary>>, acc) do
    part = if char_unreserved?(byte), do: <<byte>>, else: percent(byte)
    encode_form_bytes(rest, [part | acc])
  end

  defp percent(byte) do
    hex = "0123456789ABCDEF"
    ["%", :binary.part(hex, div(byte, 16), 1), :binary.part(hex, rem(byte, 16), 1)]
  end

  @spec encode_query([{binary(), binary()}] | map()) :: binary()
  def encode_query(pairs) when is_map(pairs), do: encode_query(:maps.to_list(pairs))

  def encode_query(pairs) when is_list(pairs) do
    :erlang.iolist_to_binary(encode_pairs(pairs, []))
  end

  defp encode_pairs([], acc), do: reverse(acc, [])

  defp encode_pairs([{key, value} | rest], []) do
    encode_pairs(rest, [[encode_www_form(as_binary(key)), "=", encode_www_form(as_binary(value))]])
  end

  defp encode_pairs([{key, value} | rest], acc) do
    encode_pairs(rest, [
      ["&", encode_www_form(as_binary(key)), "=", encode_www_form(as_binary(value))] | acc
    ])
  end

  defp as_binary(value) when is_binary(value), do: value
  defp as_binary(value) when is_atom(value), do: :erlang.atom_to_binary(value)
  defp as_binary(value) when is_integer(value), do: :erlang.integer_to_binary(value)

  @spec query_decoder(binary()) :: function()
  def query_decoder(query) when is_binary(query) do
    fn tagged_acc, reducer -> query_reduce(query, tagged_acc, reducer) end
  end

  defp query_reduce(_query, {:halt, acc}, _reducer), do: {:halted, acc}

  defp query_reduce(query, {:suspend, acc}, reducer),
    do: {:suspended, acc, fn tagged_acc -> query_reduce(query, tagged_acc, reducer) end}

  defp query_reduce("", {:cont, acc}, _reducer), do: {:done, acc}

  defp query_reduce(query, {:cont, acc}, reducer) do
    {pair, rest} = split_once(query, "&")
    {key, value} = split_once(pair, "=")
    next = reducer.({decode_form(key), decode_form(value || "")}, acc)
    query_reduce(rest || "", next, reducer)
  end

  defp reverse([], acc), do: acc
  defp reverse([item | rest], acc), do: reverse(rest, [item | acc])

  defp decode_form(binary), do: binary |> :binary.replace("+", " ", [:global]) |> decode()

  @spec decode_www_form(binary()) :: binary()
  def decode_www_form(binary) when is_binary(binary), do: decode_form(binary)

  @spec decode(binary()) :: binary()
  def decode(input) when is_binary(input), do: decode_bytes(input, [])

  defp decode_bytes(<<>>, acc), do: :erlang.iolist_to_binary(reverse(acc, []))

  defp decode_bytes(<<?%, hi, lo, rest::binary>>, acc) do
    case {hex_value(hi), hex_value(lo)} do
      {h, l} when is_integer(h) and is_integer(l) ->
        decode_bytes(rest, [<<h * 16 + l>> | acc])

      _ ->
        decode_bytes(<<hi, lo, rest::binary>>, ["%" | acc])
    end
  end

  defp decode_bytes(<<byte, rest::binary>>, acc), do: decode_bytes(rest, [<<byte>> | acc])

  defp hex_value(char) when char in ?0..?9, do: char - ?0
  defp hex_value(char) when char in ?A..?F, do: char - ?A + 10
  defp hex_value(char) when char in ?a..?f, do: char - ?a + 10
  defp hex_value(_), do: nil

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end

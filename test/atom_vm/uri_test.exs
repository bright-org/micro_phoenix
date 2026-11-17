defmodule AtomVM.URITest do
  use ExUnit.Case

  alias AtomVM.URI, as: TargetURI

  test "parses an Ecto connection URL into URI fields" do
    url = "ecto://user:p%40ss@db.example:5432/app?ssl=true&timeout=1000#section"
    assert Map.from_struct(TargetURI.parse(url)) == Map.from_struct(URI.parse(url))
  end

  test "parses absolute, relative, network-path, and IPv6 URLs like URI" do
    for url <- [
          "https://[::1]:8443/a?x=1#frag",
          "http://example.com",
          "//example.com/a",
          "a/b?x=1",
          "?x=1",
          "#frag",
          "",
          "http://user:pass@host:bad/a"
        ] do
      assert Map.from_struct(TargetURI.parse(url)) == Map.from_struct(URI.parse(url)), url
    end
  end

  test "parses mixed-case schemes, repeated @, and numeric port prefixes" do
    for url <- [
          "HTTP://EXAMPLE.COM/p",
          "https://a@b@host/x",
          "http://host:12abc/x",
          "ws://host/socket"
        ] do
      assert Map.from_struct(TargetURI.parse(url)) == Map.from_struct(URI.parse(url)), url
    end
  end

  test "parse reads the bracketed IPv6 host despite trailing authority text" do
    for url <- ["http://[::1]tail/a", "http://[::1]tail:8080/a", "http://[::1]]/a"] do
      assert Map.from_struct(TargetURI.parse(url)) == Map.from_struct(URI.parse(url)), url
    end
  end

  test "parse returns an empty host for an unclosed IPv6 authority" do
    url = "http://[::1/a"
    assert Map.from_struct(TargetURI.parse(url)) == Map.from_struct(URI.parse(url))
  end

  test "decodes escaped Ecto credentials without changing plus signs" do
    assert TargetURI.decode("p%40ss+word%2Fok") == URI.decode("p%40ss+word%2Fok")
  end

  test "decodes form-encoded values like URI for Plug.Conn.Query" do
    for value <- ["sort", "hello+world", "a%2Bb", "%E3%81%82", "%25", "%2G", "%", "a+b%20c"] do
      assert TargetURI.decode_www_form(value) == URI.decode_www_form(value), value
    end
  end

  test "normalizes Req URL strings through new! and to_string" do
    for url <- [
          "",
          "https://example.com:443/a?q=hello#f",
          "http://user:pass@host:8080/x",
          "//[::1]/a"
        ] do
      assert Map.from_struct(TargetURI.new!(url)) == Map.from_struct(URI.new!(url))
      assert TargetURI.to_string(TargetURI.new!(url)) == URI.to_string(URI.new!(url))
    end
  end

  test "parse accepts an existing URI struct as in Ecto error formatting" do
    url = "ecto://host/db?timeout=bad"
    assert TargetURI.parse(TargetURI.parse(url)) == TargetURI.parse(url)
    assert URI.parse(URI.parse(url)) == URI.parse(url)
  end

  test "URI structs interpolate as URLs in Ecto errors" do
    for url <- ["ecto://host/db?timeout=bad", "https://example.com/a b", "/relative?p=1"] do
      assert to_string(TargetURI.parse(url)) == to_string(URI.parse(url))
      assert "parsed: #{TargetURI.parse(url)}" == "parsed: #{URI.parse(url)}"
    end
  end

  test "allows an empty port before a query or fragment" do
    for url <- ["http://host:?x=1", "http://host:#f"] do
      assert Map.from_struct(TargetURI.new!(url)) == Map.from_struct(URI.new!(url)), url
    end
  end

  test "rejects malformed Req URLs with matching error details" do
    for url <- ["http://foo:bad/a", "https://[::1", "http://foo/a b"] do
      standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
      target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
      assert Map.from_struct(target_error) == Map.from_struct(standard_error)
      assert Exception.message(target_error) == Exception.message(standard_error)
    end
  end

  test "new! rejects repeated @ in authority like URI" do
    url = "http://user@@host/a"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "new! rejects text after an IPv6 authority bracket like URI" do
    url = "http://[::1]tail/a"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "new! rejects bracketed non-IPv6 hosts like URI" do
    url = "http://[notipv6]/"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "new! rejects an incomplete IPv6 address like URI" do
    url = "http://[1:2]/"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "new! accepts compressed and mapped IPv6 addresses like URI" do
    for url <- ["http://[::1]/", "http://[1:2:3:4:5:6:7:8]/", "http://[::ffff:192.0.2.1]/"] do
      assert Map.from_struct(TargetURI.new!(url)) == Map.from_struct(URI.new!(url))
    end
  end

  test "new! rejects a backslash in the host like URI" do
    url = "http://foo\\bar/"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "new! rejects non-ASCII host bytes like URI" do
    url = "https://例.jp/a"
    standard_error = assert_raise URI.Error, fn -> URI.new!(url) end
    target_error = assert_raise AtomVM.URI.Error, fn -> TargetURI.new!(url) end
    assert Map.from_struct(target_error) == Map.from_struct(standard_error)
  end

  test "encodes Req paths, form values, and query parameters" do
    for path <- ["/a b/é", "a?b#c", "hello~world"] do
      assert TargetURI.encode(path, &(&1 == ?/ or TargetURI.char_unreserved?(&1))) ==
               URI.encode(path, &(&1 == ?/ or URI.char_unreserved?(&1)))
    end

    for data <- [[{"name", "a b"}, {"q", "x&y"}], [{"é", "東京"}]] do
      assert TargetURI.encode_query(data) == URI.encode_query(data)
    end

    assert TargetURI.encode_www_form("a b+é") == URI.encode_www_form("a b+é")
    assert TargetURI.default_port("https") == URI.default_port("https")
  end

  test "resolves Req redirect locations against a base URL" do
    base = "https://example.com/a/b?old=1"

    for location <- [
          "next",
          "../c?x=1",
          "/root",
          "?fresh=1",
          "#section",
          "//other.test/z",
          "http://else.test/q"
        ] do
      expected = URI.merge(URI.parse(base), URI.parse(location))
      actual = TargetURI.merge(TargetURI.parse(base), TargetURI.parse(location))
      assert TargetURI.to_string(actual) == URI.to_string(expected), location
    end
  end

  test "resolves dot segments and trailing-slash redirects" do
    base = "https://example.com/a/b"

    for location <- [".", "..", "./", "../", "../c/", "../../d", "a/../b", "", "?", "#"] do
      expected = URI.merge(URI.parse(base), URI.parse(location)) |> URI.to_string()

      actual =
        TargetURI.merge(TargetURI.parse(base), TargetURI.parse(location)) |> TargetURI.to_string()

      assert actual == expected, location
    end
  end

  test "matches Req redirects that remove an empty path segment" do
    for location <- ["/a//../b", "/a//..", "/a//../.."] do
      base = "https://example.com/a/b"
      expected = URI.merge(URI.parse(base), URI.parse(location))
      actual = TargetURI.merge(TargetURI.parse(base), TargetURI.parse(location))
      assert Map.from_struct(actual) == Map.from_struct(expected), location
    end
  end

  test "matches Req redirects that resolve above the root" do
    for base <- ["http://example.com", "http://example.com/a/b"],
        location <- ["..", "../..", "/..", "../"] do
      expected = URI.merge(URI.parse(base), URI.parse(location))
      actual = TargetURI.merge(TargetURI.parse(base), TargetURI.parse(location))
      assert Map.from_struct(actual) == Map.from_struct(expected), inspect({base, location})
    end
  end

  test "matches Req redirects with a scheme but no authority" do
    for base <- ["http://example.com/a", "https://example.com:444/a"],
        location <- ["http:/x", "https:/x"] do
      expected = URI.merge(URI.parse(base), URI.parse(location))
      actual = TargetURI.merge(TargetURI.parse(base), TargetURI.parse(location))
      assert Map.from_struct(actual) == Map.from_struct(expected), inspect({base, location})
    end
  end

  test "decodes Ecto query pairs including spaces and escaped separators" do
    query = "ssl=true&password=p%26q+z&empty=&flag&timeout=1000"
    assert Enum.to_list(TargetURI.query_decoder(query)) == Enum.to_list(URI.query_decoder(query))
  end

  test "query_decoder returns a lazy two-argument enumerable" do
    query = "a=1&&b=2"
    actual = TargetURI.query_decoder(query)
    expected = URI.query_decoder(query)

    assert is_function(actual, 2)
    assert Enum.to_list(actual) == Enum.to_list(expected)
    assert Enum.take(actual, 1) == Enum.take(expected, 1)

    assert actual.({:suspend, []}, fn pair, acc -> {:cont, [pair | acc]} end) |> elem(0) ==
             :suspended
  end

  test "keeps empty query pairs as the standard decoder does" do
    for query <- ["", "&", "a&&b", "foo=bar=baz"] do
      assert Enum.to_list(TargetURI.query_decoder(query)) ==
               Enum.to_list(URI.query_decoder(query)),
             query
    end
  end
end

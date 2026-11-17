defmodule AtomVM.PathCompatTest do
  use ExUnit.Case

  test "the Path replacement matches the host Path for binary inputs" do
    source = Mix.Tasks.Phoenix.Atomvm.CompatBeams.path_stub_source()

    probe_source =
      source
      |> String.replace("defmodule Path do", "defmodule AtomVM.PathReplacementProbe do")
      |> String.replace("@compile {:autoload, false}", "")

    [{probe, _bytecode}] = Code.compile_string(probe_source)

    paths = [
      "",
      "/",
      "//",
      "///",
      "a",
      "a/",
      "a//",
      "/a",
      "//a",
      "//a//b",
      "/a/b/",
      "a/b/",
      ".",
      "..",
      ".hidden",
      ".hidden/.file",
      "x/.file",
      "a.b/c.d",
      "a.txt",
      ".bashrc",
      "a.tar.gz",
      "a.",
      "..a",
      "a...",
      "...",
      "日本語.txt",
      "foo bar/baz qux.txt",
      "~",
      "~/foo",
      "\\",
      "a\\b",
      "a/./b",
      "a/..",
      "/.hidden"
    ]

    pairs = [
      {"x.svg", ".svg"},
      {"x.svg", ".png"},
      {"a.tar.gz", ".gz"},
      {"a.tar.gz", ".tar.gz"},
      {"a", "a"},
      {"a.b", ""},
      {"", ""},
      {".", "."},
      {"a.", "."},
      {"日本語.txt", ".txt"},
      {"x/b", "b"},
      {"x/b", "x/b"},
      {"/jam.src/kalle.jam", ".erl"},
      {"/jam.src/foo.erl", ".erl"},
      {"a.b/c.d", ".d"},
      {"dir/", "/"},
      {".hidden/.file", ".file"},
      {"a...b", ".b"}
    ]

    join_lists = [
      ["a", "b"],
      ["a", "b", "c"],
      ["", "b"],
      ["a", ""],
      ["/", "foo", "bar/"],
      ["~", "foo"],
      ["a", "/b"],
      ["/"],
      ["a"],
      [""],
      ["a", "/", "b"],
      ["//", "a"],
      [".hidden", ".file"],
      ["日本語", "パス"]
    ]

    mismatches =
      Enum.reduce(paths, [], fn path, acc ->
        checks = [
          {"split", Path.split(path), apply(probe, :split, [path])},
          {"dirname", Path.dirname(path), apply(probe, :dirname, [path])},
          {"basename", Path.basename(path), apply(probe, :basename, [path])},
          {"rootname", Path.rootname(path), apply(probe, :rootname, [path])},
          {"extname", Path.extname(path), apply(probe, :extname, [path])}
        ]

        Enum.reduce(checks, acc, fn {op, real, replaced}, acc2 ->
          if real == replaced, do: acc2, else: acc2 ++ [{op, path, real, replaced}]
        end)
      end)

    mismatches =
      Enum.reduce(paths, mismatches, fn left, acc ->
        Enum.reduce(paths, acc, fn right, acc2 ->
          real = Path.join(left, right)
          replaced = apply(probe, :join, [left, right])

          if real == replaced,
            do: acc2,
            else: acc2 ++ [{"join/2", {left, right}, real, replaced}]
        end)
      end)

    mismatches =
      Enum.reduce(join_lists, mismatches, fn list, acc ->
        real = Path.join(list)
        replaced = apply(probe, :join, [list])

        if real == replaced, do: acc, else: acc ++ [{"join/1", list, real, replaced}]
      end)

    mismatches =
      Enum.reduce(pairs, mismatches, fn {name, ext}, acc ->
        checks = [
          {"basename/2", {name, ext}, Path.basename(name, ext),
           apply(probe, :basename, [name, ext])},
          {"rootname/2", {name, ext}, Path.rootname(name, ext),
           apply(probe, :rootname, [name, ext])}
        ]

        Enum.reduce(checks, acc, fn {op, input, real, replaced}, acc2 ->
          if real == replaced, do: acc2, else: acc2 ++ [{op, input, real, replaced}]
        end)
      end)

    assert mismatches == []
  end

  test "the Elixir.Path replacement is copied into the app ebin and stdlib extras avm" do
    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_elixir_stdlib_avm!()

    beam = Path.join(Mix.Project.compile_path(), "Elixir.Path.beam")
    assert File.exists?(beam)
    assert :binary.match(File.read!(beam), "rootname_scan") != :nomatch

    avm = Path.expand("avm_deps/elixir_stdlib_extras.avm")
    assert File.stat!(avm).size > 0
  end
end

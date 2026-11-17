defmodule AtomVM.EnumerableFunctionSourceTest do
  use ExUnit.Case

  test "the AtomVM-only source builds the Enumerable.Function protocol implementation" do
    source = Path.expand("../../atomvm/enumerable_function.ex", __DIR__)

    output_dir =
      Path.expand(
        "../../_build/uri_enumerable_source_test/#{System.unique_integer([:positive])}",
        __DIR__
      )

    File.mkdir_p!(output_dir)
    on_exit(fn -> File.rm_rf!(output_dir) end)

    {output, status} =
      System.cmd("elixirc", ["--ignore-module-conflict", "-o", output_dir, source],
        stderr_to_stdout: true
      )

    assert status == 0, output

    beam = Path.join(output_dir, "Elixir.Enumerable.Function.beam")

    assert {:ok, {Enumerable.Function, [exports: exports]}} =
             :beam_lib.chunks(String.to_charlist(beam), [:exports])

    for entry <- [count: 1, member?: 2, reduce: 3, slice: 1] do
      assert entry in exports
    end
  end
end

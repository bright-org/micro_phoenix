defmodule AtomVM.EnumerablePackagingTest do
  use ExUnit.Case

  test "the built-in packer includes function enumeration without a separate dependency" do
    output_dir = Path.expand("../../_build/uri_enumerable_test", __DIR__)
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "function-#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(output) end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_enumerable_function_avm!(output)
    assert File.stat!(output).size > 0
  end
end

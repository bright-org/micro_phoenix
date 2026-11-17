defmodule AtomVM.ListPackagingTest do
  use ExUnit.Case

  test "the compatibility packer includes List.keystore without changing AtomVM" do
    output_dir = Path.expand("../../_build/list_compat_test", __DIR__)
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "list-#{System.unique_integer([:positive])}.avm")
    compiled_list = Path.join(Mix.Project.compile_path(), "Elixir.List.beam")
    previous = File.read(compiled_list)

    on_exit(fn ->
      File.rm(output)

      case previous do
        {:ok, beam} -> File.write!(compiled_list, beam)
        {:error, :enoent} -> File.rm(compiled_list)
      end
    end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_list_avm!(output)
    assert File.stat!(output).size > 0

    assert {:ok, {List, [exports: exports]}} =
             :beam_lib.chunks(String.to_charlist(compiled_list), [:exports])

    assert {:keystore, 4} in exports
  end
end

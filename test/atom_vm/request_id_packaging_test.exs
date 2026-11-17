defmodule AtomVM.RequestIdPackagingTest do
  use ExUnit.Case

  test "target-only replacements exclude the upstream dependency BEAMs" do
    upstream = Mix.Tasks.Atomvm.Packbeam.runtime_deps_beams()

    assert Enum.any?(upstream, &(Path.basename(&1) == "telemetry.beam"))
    assert Enum.any?(upstream, &(Path.basename(&1) == "Elixir.Plug.RequestId.beam"))
    assert Enum.any?(upstream, &(Path.basename(&1) == "Elixir.Plug.Conn.beam"))
    assert Enum.any?(upstream, &(Path.basename(&1) == "Elixir.Plug.Conn.Query.beam"))
    assert Enum.any?(upstream, &(Path.basename(&1) == "Elixir.Plug.Static.beam"))
    assert Enum.any?(upstream, &(Path.basename(&1) == "Elixir.Plug.Static.InvalidPathError.beam"))

    replacement_deps = Mix.Tasks.Phoenix.Atomvm.Packbeam.target_dependency_beams(upstream)

    refute Enum.any?(replacement_deps, &(Path.basename(&1) == "telemetry.beam"))
    refute Enum.any?(replacement_deps, &(Path.basename(&1) == "Elixir.Plug.RequestId.beam"))
    refute Enum.any?(replacement_deps, &(Path.basename(&1) == "Elixir.Plug.Conn.beam"))
    refute Enum.any?(replacement_deps, &(Path.basename(&1) == "Elixir.Plug.Conn.Query.beam"))
    refute Enum.any?(replacement_deps, &(Path.basename(&1) == "Elixir.Plug.Static.beam"))

    refute Enum.any?(
             replacement_deps,
             &(Path.basename(&1) == "Elixir.Plug.Static.InvalidPathError.beam")
           )

    replaced_count =
      Enum.count(
        upstream,
        &(Path.basename(&1) in [
            "telemetry.beam",
            "Elixir.Plug.RequestId.beam",
            "Elixir.Plug.Conn.beam",
            "Elixir.Plug.Conn.Query.beam",
            "Elixir.Plug.Static.beam",
            "Elixir.Plug.Static.InvalidPathError.beam"
          ])
      )

    assert length(replacement_deps) == length(upstream) - replaced_count
  end

  test "the target-only Plug.Conn.Query is bundled by the compatibility packer" do
    output_dir = Path.join(Mix.Project.build_path(), "query_test")
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "query-#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(output) end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_query_avm!(output)
    assert File.stat!(output).size > 0
  end

  test "the target-only Plug.Conn is bundled by the compatibility packer" do
    output_dir = Path.join(Mix.Project.build_path(), "conn_test")
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "conn-#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(output) end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_conn_avm!(output)
    assert File.stat!(output).size > 0
  end

  test "the target-only Plug.Static is bundled by the compatibility packer" do
    output_dir = Path.join(Mix.Project.build_path(), "static_test")
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "static-#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(output) end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_static_avm!(output)
    assert File.stat!(output).size > 0
  end

  test "the target-only Plug.RequestId is bundled by the compatibility packer" do
    output_dir = Path.join(Mix.Project.build_path(), "request_id_test")
    File.mkdir_p!(output_dir)
    output = Path.join(output_dir, "request-id-#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(output) end)

    assert :ok == Mix.Tasks.Phoenix.Atomvm.CompatBeams.write_request_id_avm!(output)
    assert File.stat!(output).size > 0
  end
end

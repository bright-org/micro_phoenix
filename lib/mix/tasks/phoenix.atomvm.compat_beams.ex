defmodule Mix.Tasks.Phoenix.Atomvm.CompatBeams do
  @moduledoc false

  # Builds AtomVM-safe stand-ins that must override host BEAM modules in the AVM.
  # Compiled in a subprocess so the Mix host keeps the real Elixir.Application.

  def ensure_avm_deps! do
    File.mkdir_p!("avm_deps")
    write_application_avm!()
    :ok
  end

  defp write_application_avm! do
    out = Path.expand("avm_deps/elixir_application.avm")
    beam_path = Path.join(System.tmp_dir!(), "Elixir.Application.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "application_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule Application do
      @moduledoc false

      def spec(:phoenix, :vsn), do: ~c"1.8.0"
      def spec(_app, _key), do: nil

      def get_env(_app, _key), do: nil
      def get_env(_app, _key, default), do: default

      def fetch_env!(app, key) do
        case get_env(app, key) do
          nil -> :erlang.error({:badarg, {app, key}})
          value -> value
        end
      end

      def fetch_env(app, key) do
        case get_env(app, key) do
          nil -> :error
          value -> {:ok, value}
        end
      end

      def put_env(_app, _key, _value), do: :ok
      def get_application(_module), do: nil
      def ensure_all_started(_app), do: {:ok, []}
      def ensure_all_started(_app, _type), do: {:ok, []}
      def stop(_app), do: :ok
      def started_applications(), do: []
      def loaded_applications(), do: []
      def app_dir(app), do: to_string(app)
      def app_dir(app, path), do: Path.join(to_string(app), path)
    end
    """)

    {_, 0} =
      System.cmd(
        "elixir",
        [
          "-e",
          """
          Code.put_compiler_option(:ignore_module_conflict, true)
          [{Application, bytecode}] = Code.compile_file(#{inspect(stub_ex)})
          File.write!(#{inspect(beam_path)}, bytecode)
          """
        ],
        stderr_to_stdout: true
      )

    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    Mix.shell().info("Wrote AtomVM Application stub -> #{out}")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end
end

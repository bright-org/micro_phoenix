defmodule Mix.Tasks.Phoenix.Atomvm.Run do
  use Mix.Task

  @shortdoc "Pack and run the app under AtomVM"

  @moduledoc """
  Runs `mix phoenix.atomvm.packbeam`, then launches the AtomVM binary.

  Requires `ATOMVM_INSTALL_PREFIX` (build directory of AtomVM), e.g.:

      export ATOMVM_INSTALL_PREFIX=/path/to/AtomVM/build
      mix phoenix.atomvm.run
  """

  alias Mix.Project

  @impl Mix.Task
  def run(args) do
    {opts, pack_args, _} =
      OptionParser.parse(args,
        strict: [pack: :boolean, port: :integer],
        aliases: [p: :port]
      )

    if Keyword.get(opts, :pack, true) do
      Mix.Task.reenable("phoenix.atomvm.packbeam")
      Mix.Task.run("phoenix.atomvm.packbeam", pack_args)
    end

    prefix =
      System.get_env("ATOMVM_INSTALL_PREFIX") ||
        Mix.raise("""
        ATOMVM_INSTALL_PREFIX is not set.

        Example (adjust to your AtomVM build dir):

            export ATOMVM_INSTALL_PREFIX=/home/linsei/Work/ElixirChip/AtomVM/build
            mix phoenix.atomvm.run
        """)

    app = Project.config()[:app]
    root = File.cwd!()

    atomvm = Path.join(prefix, "src/AtomVM")
    atomvmlib = Path.join(prefix, "libs/atomvmlib.avm")
    estdlib = Path.join(prefix, "libs/estdlib/src/estdlib.avm")
    exavmlib = Path.join(prefix, "libs/exavmlib/lib/exavmlib.avm")
    app_avm = Path.join(root, "#{app}.avm")

    Enum.each([atomvm, atomvmlib, estdlib, exavmlib, app_avm], fn path ->
      unless File.exists?(path) do
        Mix.raise("""
        missing #{path}

        ATOMVM_INSTALL_PREFIX=#{inspect(prefix)}
        Hint: set ATOMVM_INSTALL_PREFIX to your real AtomVM *build* directory
        (not a placeholder like /path/to/AtomVM/build), then re-run.
        """)
      end
    end)

    Mix.shell().info("Starting AtomVM with #{app_avm}")

    System.cmd(
      atomvm,
      [app_avm, atomvmlib, estdlib, exavmlib],
      into: IO.stream(:stdio, :line),
      cd: root
    )
  end
end

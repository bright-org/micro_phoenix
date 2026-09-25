defmodule Mix.Tasks.Phoenix.Atomvm.Migrate do
  use Mix.Task

  @shortdoc "Compile migrations, pack AVM, run Ecto.Migrator on AtomVM"

  @moduledoc """
  Host-side timing equivalent of `mix ecto.migrate` for AtomVM.

  Compiles `priv/repo/migrations/*.exs` into the app ebin, packs them into the
  AVM with a one-shot `Phoenix.AtomVM.Boot` that calls `Phoenix.AtomVM.migrate/3`
  (tuple source — no Mix / no `.exs` load on device), then launches AtomVM.

  Requires `ATOMVM_INSTALL_PREFIX` (same as `mix phoenix.atomvm.run`).
  """

  alias Mix.Project
  alias Mix.Tasks.Phoenix.Atomvm.Packbeam

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    avm_config = Keyword.get(Project.config(), :atomvm) || []

    repo =
      Keyword.get(avm_config, :repo) ||
        Mix.raise("missing atomvm: [repo: ...] in mix.exs (required for phoenix.atomvm.migrate)")

    otp_app = Keyword.get(avm_config, :otp_app, Project.config()[:app])
    start = Keyword.get(avm_config, :start, Phoenix.AtomVM.Boot)

    unless start == Phoenix.AtomVM.Boot do
      Mix.raise("atomvm: [start: ...] must be Phoenix.AtomVM.Boot, got #{inspect(start)}")
    end

    migrations = compile_migrations!(otp_app)

    if migrations == [] do
      Mix.raise("no migrations found under priv/repo/migrations/*.exs")
    end

    Packbeam.write_migrate_boot_beam!(repo, migrations, otp_app)
    Mix.shell().info("Generated migrate Boot with #{length(migrations)} migration(s)")

    Mix.Tasks.Phoenix.Atomvm.CompatBeams.ensure_avm_deps!()

    case Mix.Task.run("atomvm.packbeam", args) do
      :ok -> :ok
      {:ok, _} -> :ok
      other -> other
    end

    launch_atomvm!()
  end

  defp compile_migrations!(otp_app) do
    migrations_path = Application.app_dir(otp_app, "priv/repo/migrations")

    migrations_path =
      if File.dir?(migrations_path) do
        migrations_path
      else
        Path.join([File.cwd!(), "priv", "repo", "migrations"])
      end

    unless File.dir?(migrations_path) do
      Mix.raise("migrations directory not found: #{migrations_path}")
    end

    File.mkdir_p!(Project.compile_path())

    migrations_path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.reject(&(&1 == ".formatter.exs"))
    |> Enum.sort()
    |> Enum.map(fn file ->
      case Regex.run(~r/^(\d+)_(.+)\.exs$/, file) do
        [_, version, _] ->
          path = Path.join(migrations_path, file)
          [{mod, bytecode} | _] = Code.compile_file(path)
          beam = Path.join(Project.compile_path(), "#{Atom.to_string(mod)}.beam")
          File.write!(beam, bytecode)
          Mix.shell().info("Compiled migration #{file} -> #{inspect(mod)}")
          {String.to_integer(version), mod}

        nil ->
          Mix.raise("invalid migration filename (expected TIMESTAMP_name.exs): #{file}")
      end
    end)
  end

  defp launch_atomvm! do
    prefix =
      System.get_env("ATOMVM_INSTALL_PREFIX") ||
        Mix.raise("""
        ATOMVM_INSTALL_PREFIX is not set.

        Example:

            export ATOMVM_INSTALL_PREFIX=/home/linsei/Work/ElixirChip/AtomVM/build
            mix phoenix.atomvm.migrate
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
        Mix.raise("missing #{path}")
      end
    end)

    Mix.shell().info("Starting AtomVM migrate with #{app_avm}")

    env = port_env()

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(atomvm)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args,
           Enum.map([app_avm, atomvmlib, estdlib, exavmlib], &String.to_charlist/1)},
          {:cd, String.to_charlist(root)},
          {:env, env}
        ]
      )

    case await_migrate_marker(port, "", 120_000) do
      {:ok, output} ->
        stop_port(port)

        if String.contains?(output, "atomvm_migrate:{:error") or
             String.contains?(output, "migrate_error") or
             String.contains?(output, "migrate_catch") do
          Mix.raise("AtomVM migrate reported an error (see output above)")
        end

        :ok

      {:error, :timeout, _output} ->
        stop_port(port)
        Mix.raise("AtomVM migrate timed out waiting for atomvm_migrate: marker")

      {:error, {:exit, status}, _output} ->
        Mix.raise("AtomVM exited with status #{status} before atomvm_migrate: marker")
    end
  end

  defp port_env do
    base = for {k, v} <- System.get_env(), do: {String.to_charlist(k), String.to_charlist(v)}

    ld =
      case System.get_env("ATOMVM_MBEDTLS_LIBDIR") do
        nil -> System.get_env("LD_LIBRARY_PATH") || ""
        dir ->
          case System.get_env("LD_LIBRARY_PATH") do
            nil -> dir
            "" -> dir
            existing -> dir <> ":" <> existing
          end
      end

    List.keystore(base, ~c"LD_LIBRARY_PATH", 0, {~c"LD_LIBRARY_PATH", String.to_charlist(ld)})
  end

  defp await_migrate_marker(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        acc = acc <> data
        IO.write(data)

        if String.contains?(acc, "atomvm_migrate:") do
          {:ok, acc}
        else
          await_migrate_marker(port, acc, timeout)
        end

      {^port, {:exit_status, status}} ->
        {:error, {:exit, status}, acc}
    after
      timeout ->
        {:error, :timeout, acc}
    end
  end

  defp stop_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) ->
        _ = System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)

      _ ->
        :ok
    end

    Port.close(port)
  rescue
    _ -> :ok
  end
end

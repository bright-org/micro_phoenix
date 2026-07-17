defmodule Mix.Tasks.Phoenix.Atomvm.Packbeam do
  use Mix.Task

  @shortdoc "Generate Phoenix.AtomVM.Boot and pack the app AVM"

  @moduledoc """
  Packs a Phoenix-compatible app for AtomVM without an app-local start module in `lib/`.

  Reads `:atomvm` from the host project's `mix.exs`:

      atomvm: [
        start: Phoenix.AtomVM.Boot,
        router: MyAppWeb.Router,
        repo: MyApp.Repo,
        port: 8080
      ]

  Generates `Phoenix.AtomVM.Boot` into the app ebin (required by ExAtomVM), then runs
  `mix atomvm.packbeam`.
  """

  alias Mix.Project

  @boot_module Phoenix.AtomVM.Boot

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    avm_config = Keyword.get(Project.config(), :atomvm) || []

    router =
      Keyword.get(avm_config, :router) ||
        Mix.raise("""
        missing atomvm: [router: ...] in mix.exs

        Example:

            atomvm: [
              start: Phoenix.AtomVM.Boot,
              router: MyAppWeb.Router,
              repo: MyApp.Repo,
              port: 8080
            ]
        """)

    repo = Keyword.get(avm_config, :repo)
    port = Keyword.get(avm_config, :port, 8080)
    otp_app = Keyword.get(avm_config, :otp_app, Project.config()[:app])

    start = Keyword.get(avm_config, :start, @boot_module)

    unless start == @boot_module do
      Mix.raise("atomvm: [start: ...] must be #{inspect(@boot_module)}, got #{inspect(start)}")
    end

    write_boot_beam!(router, repo, port, otp_app)
    Mix.shell().info("Generated #{inspect(@boot_module)} -> #{boot_beam_path()}")

    Mix.Tasks.Phoenix.Atomvm.CompatBeams.ensure_avm_deps!()

    ensure_colocated_stubs!()
    _ = Mix.Task.rerun("assets.build")

    case Mix.Task.run("atomvm.packbeam", args) do
      :ok -> :ok
      {:ok, _} -> :ok
      other -> other
    end
  end

  @doc false
  def write_boot_beam!(router, repo, port, otp_app)
      when is_atom(router) and (is_atom(repo) or is_nil(repo)) and is_integer(port) and
             is_atom(otp_app) do
    opts =
      [port: port, otp_app: otp_app]
      |> then(fn opts -> if repo, do: Keyword.put(opts, :repo, repo), else: opts end)

    source = """
    defmodule #{inspect(@boot_module)} do
      @moduledoc false

      def start do
        Phoenix.AtomVM.run(#{inspect(router)}, #{inspect(opts)})
      end
    end
    """

    File.mkdir_p!(Project.compile_path())

    boot_module = @boot_module
    [{^boot_module, bytecode}] = Code.compile_string(source)
    File.write!(boot_beam_path(), bytecode)
    :ok
  end

  defp boot_beam_path do
    Path.join(Project.compile_path(), "#{Atom.to_string(@boot_module)}.beam")
  end

  defp ensure_colocated_stubs! do
    app = Project.config()[:app]
    dir = Path.join([Mix.Project.build_path(), "phoenix-colocated", to_string(app)])
    File.mkdir_p!(dir)

    css = Path.join(dir, "colocated.css")
    js = Path.join(dir, "index.js")

    unless File.exists?(css), do: File.write!(css, "/* colocated css stub */\n")
    unless File.exists?(js), do: File.write!(js, "export const hooks = {}\n")
    :ok
  end
end

defmodule Mix.Tasks.Phoenix.Atomvm.CompatBeams do
  @moduledoc false

  # Builds AtomVM-safe stand-ins that must override host BEAM modules in the AVM.
  # Compiled in a subprocess so the Mix host keeps the real Elixir.Application.

  def ensure_avm_deps! do
    File.mkdir_p!("avm_deps")
    write_application_avm!()
    write_telemetry_avm!()
    write_code_avm!()
    write_system_avm!()
    write_process_avm!()
    write_list_avm!(Path.expand("avm_deps/elixir_list.avm"))
    write_enum_avm!()
    write_enumerable_function_avm!(Path.expand("avm_deps/elixir_enumerable_function.avm"))
    write_request_id_avm!(Path.expand("avm_deps/plug_request_id.avm"))
    write_query_avm!(Path.expand("avm_deps/plug_conn_query.avm"))
    write_conn_avm!(Path.expand("avm_deps/plug_conn.avm"))
    write_static_avm!(Path.expand("avm_deps/plug_static.avm"))
    write_map_avm!()
    write_access_avm!()
    write_erlang_application_avm!()
    write_elixir_stdlib_avm!()
    write_calendar_avm!()
    :ok
  end

  def write_enumerable_function_avm!(output) do
    source = Path.expand("../../../atomvm/enumerable_function.ex", __DIR__)

    build_dir =
      Path.join(Mix.Project.build_path(), "uri_enumerable_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      {message, status} =
        System.cmd("elixirc", ["--ignore-module-conflict", "-o", build_dir, source],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise(message)

      beam = Path.join(build_dir, "Elixir.Enumerable.Function.beam")
      ExAtomVM.PackBEAM.make_avm([{beam, :beam}], output)
      :ok
    after
      File.rm_rf!(build_dir)
    end
  end

  def write_request_id_avm!(output) do
    source = Path.expand("../../../atomvm/plug_request_id.ex", __DIR__)

    build_dir =
      Path.join(Mix.Project.build_path(), "plug_request_id_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      {message, status} =
        System.cmd(
          "elixirc",
          [
            "--ignore-module-conflict",
            "-pa",
            Path.join(Mix.Project.build_path(), "lib/plug/ebin"),
            "-o",
            build_dir,
            source
          ],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise(message)

      beam = Path.join(build_dir, "Elixir.Plug.RequestId.beam")
      ExAtomVM.PackBEAM.make_avm([{beam, :beam}], output)
      :ok
    after
      File.rm_rf!(build_dir)
    end
  end

  def write_query_avm!(output) do
    source_path = Path.join(Mix.Project.deps_path(), "plug/lib/plug/conn/query.ex")
    source = File.read!(source_path)

    for call <- ["URI.decode_www_form(", "URI.encode_www_form("] do
      unless String.contains?(source, call), do: Mix.raise("missing #{call} in #{source_path}")
    end

    build_dir =
      Path.join(Mix.Project.build_path(), "plug_conn_query_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      patched_path = Path.join(build_dir, "query.ex")

      source =
        source
        |> String.replace("URI.decode_www_form(", "AtomVM.URI.decode_www_form(")
        |> String.replace("URI.encode_www_form(", "AtomVM.URI.encode_www_form(")

      File.write!(patched_path, source)

      {message, status} =
        System.cmd(
          "elixirc",
          [
            "--ignore-module-conflict",
            "-pa",
            Path.join(Mix.Project.build_path(), "lib/plug/ebin"),
            "-o",
            build_dir,
            patched_path
          ],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise("Plug.Conn.Query compile failed:\n#{message}")

      beam = Path.join(build_dir, "Elixir.Plug.Conn.Query.beam")
      :ok = ExAtomVM.PackBEAM.make_avm([{beam, :beam}], output)
    after
      File.rm_rf!(build_dir)
    end
  end

  def write_conn_avm!(output) do
    source_path = Path.join(Mix.Project.deps_path(), "plug/lib/plug/conn.ex")
    source = File.read!(source_path)
    null_check = ~S[if file =~ "\0" do]

    if length(:binary.matches(source, null_check)) != 1 do
      Mix.raise("expected one #{null_check} in #{source_path}")
    end

    build_dir =
      Path.join(Mix.Project.build_path(), "plug_conn_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      patched_path = Path.join(build_dir, "conn.ex")

      patched =
        String.replace(
          source,
          null_check,
          ~S[if :binary.match(file, <<0>>) != :nomatch do]
        )

      File.write!(patched_path, patched)

      {message, status} =
        System.cmd(
          "elixirc",
          [
            "--ignore-module-conflict",
            "-pa",
            Path.join(Mix.Project.build_path(), "lib/plug/ebin"),
            "-o",
            build_dir,
            patched_path
          ],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise("Plug.Conn compile failed:\n#{message}")

      beam = Path.join(build_dir, "Elixir.Plug.Conn.beam")
      :ok = ExAtomVM.PackBEAM.make_avm([{beam, :beam}], output)
    after
      File.rm_rf!(build_dir)
    end
  end

  def write_static_avm!(output) do
    source_path = Path.join(Mix.Project.deps_path(), "plug/lib/plug/static.ex")
    source = File.read!(source_path)
    call = "&URI.decode/1"

    if length(:binary.matches(source, call)) != 2 do
      Mix.raise("expected two #{call} calls in #{source_path}")
    end

    build_dir =
      Path.join(Mix.Project.build_path(), "plug_static_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      patched_path = Path.join(build_dir, "static.ex")

      invalid_path_source = """
        defp invalid_path?(list) do
          invalid_path?(list, :binary.compile_pattern(["/", "\\\\", ":", "\\0"]))
        end

        defp invalid_path?([h | _], _match) when h in [".", "..", ""], do: true
        defp invalid_path?([h | t], match), do: String.contains?(h, match) or invalid_path?(t)
        defp invalid_path?([], _match), do: false
      """

      target_invalid_path = """
        defp invalid_path?([h | _]) when h in [".", "..", ""], do: true
        defp invalid_path?([h | t]),
          do: :binary.match(h, ["/", "\\\\", ":", "\\0"]) != :nomatch or invalid_path?(t)
        defp invalid_path?([]), do: false
      """

      file_info_source = """
        defp regular_file_info(path) do
          case :prim_file.read_file_info(path) do
            {:ok, file_info(type: :regular) = file_info} ->
              file_info

            _ ->
              nil
          end
        end
      """

      target_file_info = """
        defp regular_file_info(path) do
          case Phoenix.AtomVM.PrivFile.read(path) do
            {:ok, body} -> file_info(type: :regular, size: byte_size(body))
            :error -> nil
          end
        end
      """

      etag_source =
        "file_info(size: size, mtime: mtime) = file_info\n        <<?\", {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)::binary, ?\">>"

      target_etag =
        "{:ok, body} = Phoenix.AtomVM.PrivFile.read(path)\n        <<?\", :erlang.crc32(body) |> Integer.to_string(16)::binary, ?\">>"

      if length(:binary.matches(source, invalid_path_source)) != 1 do
        Mix.raise("expected invalid_path? definition in #{source_path}")
      end

      for anchor <- [file_info_source, etag_source] do
        if length(:binary.matches(source, anchor)) != 1 do
          Mix.raise("expected Plug.Static source anchor in #{source_path}: #{anchor}")
        end
      end

      patched =
        source
        |> String.replace(call, "&AtomVM.URI.decode/1")
        |> String.replace(invalid_path_source, target_invalid_path)
        |> String.replace(file_info_source, target_file_info)
        |> String.replace(etag_source, target_etag)

      File.write!(patched_path, patched)

      {message, status} =
        System.cmd(
          "elixirc",
          [
            "--ignore-module-conflict",
            "-pa",
            Path.join(Mix.Project.build_path(), "lib/plug/ebin"),
            "-o",
            build_dir,
            patched_path
          ],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise("Plug.Static compile failed:\n#{message}")

      beams =
        Path.wildcard(Path.join(build_dir, "*.beam"))
        |> Enum.map(&{&1, :beam})

      :ok = ExAtomVM.PackBEAM.make_avm(beams, output)
    after
      File.rm_rf!(build_dir)
    end
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

      def get_env(:postgrex, :type_server_timeout), do: 60_000
      def get_env(:postgrex, :type_server_reap_after), do: 180_000
      def get_env(:postgrex, :json_library), do: Jason
      def get_env(:gettext, :default_locale), do: "en"
      def get_env(:gettext, :default_domain), do: "default"
      def get_env(_app, _key), do: nil
      def get_env(app, key, default), do: get_env(app, key) || default

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

    compile_stub!(stub_ex, beam_path, Application)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    Mix.shell().info("Wrote AtomVM Application stub -> #{out}")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # Host telemetry uses persistent_term for the handler table. AtomVM has no
  # persistent_term, so ship a no-op :telemetry that overrides the Hex module.
  # Written into the app ebin as well so the app AVM (loaded first) wins.
  defp write_telemetry_avm! do
    out = Path.expand("avm_deps/telemetry_stub.avm")
    beam_path = Path.join(System.tmp_dir!(), "telemetry.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "telemetry_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule :telemetry do
      @moduledoc false

      def execute(_event, _measurements, _metadata), do: :ok
      def attach(_id, _events, _fun, _config), do: :ok
      def attach_many(_id, _events, _fun, _config), do: :ok
      def detach(_id), do: :ok
      def list_handlers(_event), do: []

      def span(_event, _metadata, fun) when is_function(fun, 0) do
        fun.()
      end
    end
    """)

    compile_stub!(stub_ex, beam_path, :telemetry)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    File.cp!(beam_path, Path.join(Mix.Project.compile_path(), "telemetry.beam"))
    Mix.shell().info("Wrote AtomVM telemetry stub -> #{out} (and app ebin)")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # AtomVM's Code has ensure_compiled?/1 but not ensure_loaded?/1.
  defp write_code_avm! do
    out = Path.expand("avm_deps/elixir_code.avm")
    beam_path = Path.join(System.tmp_dir!(), "Elixir.Code.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "code_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule Code do
      @moduledoc false
      @compile {:autoload, false}

      def ensure_compiled(module), do: :code.ensure_loaded(module)

      def ensure_compiled?(module) do
        match?({:module, ^module}, ensure_compiled(module))
      end

      def ensure_loaded(module), do: ensure_compiled(module)
      def ensure_loaded?(module), do: ensure_compiled?(module)
    end
    """)

    compile_stub!(stub_ex, beam_path, Code)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    File.cp!(beam_path, Path.join(Mix.Project.compile_path(), "Elixir.Code.beam"))
    Mix.shell().info("Wrote AtomVM Code stub -> #{out} (and app ebin)")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # AtomVM's System lacks get_env/1 used by Postgrex.Utils.default_opts/1.
  defp write_system_avm! do
    out = Path.expand("avm_deps/elixir_system.avm")
    beam_path = Path.join(System.tmp_dir!(), "Elixir.System.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "system_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule System do
      @moduledoc false
      @compile {:autoload, false}

      def get_env(varname) when is_binary(varname) do
        case :os.getenv(:erlang.binary_to_list(varname)) do
          false -> nil
          value -> :erlang.list_to_binary(value)
        end
      end

      def get_env(varname, default) when is_binary(varname) do
        get_env(varname) || default
      end

      def monotonic_time, do: :erlang.monotonic_time()
      def monotonic_time(unit), do: :erlang.monotonic_time(normalize_time_unit(unit))
      def system_time, do: :erlang.system_time()
      def system_time(unit), do: :erlang.system_time(normalize_time_unit(unit))
      def os_time, do: :os.system_time()
      def os_time(unit), do: :os.system_time(normalize_time_unit(unit))

      def convert_time_unit(time, from, to) when is_integer(time) do
        native = to_native(time, from)
        from_native(native, to)
      end

      defp normalize_time_unit(1000), do: :millisecond
      defp normalize_time_unit(unit) when is_atom(unit), do: unit
      defp normalize_time_unit(pps) when is_integer(pps) and pps > 0, do: pps

      defp to_native(t, :native), do: t
      defp to_native(t, :nanosecond), do: t
      defp to_native(t, :microsecond), do: t * 1_000
      defp to_native(t, :millisecond), do: t * 1_000_000
      defp to_native(t, :second), do: t * 1_000_000_000
      defp to_native(t, 1000), do: t * 1_000_000
      defp to_native(t, pps) when is_integer(pps) and pps > 0, do: div(t * 1_000_000_000, pps)

      defp from_native(ns, :native), do: ns
      defp from_native(ns, :nanosecond), do: ns
      defp from_native(ns, :microsecond), do: div(ns, 1_000)
      defp from_native(ns, :millisecond), do: div(ns, 1_000_000)
      defp from_native(ns, :second), do: div(ns, 1_000_000_000)
      defp from_native(ns, 1000), do: div(ns, 1_000_000)
      defp from_native(ns, pps) when is_integer(pps) and pps > 0, do: div(ns * pps, 1_000_000_000)
    end
    """)

    compile_stub!(stub_ex, beam_path, System)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    File.cp!(beam_path, Path.join(Mix.Project.compile_path(), "Elixir.System.beam"))
    Mix.shell().info("Wrote AtomVM System stub -> #{out} (and app ebin)")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # AtomVM Process lacks put/2, get/1,2, delete/1. Pack a stand-in that keeps
  # the AtomVM-safe Process surface and adds dictionary helpers via :erlang.
  defp write_process_avm! do
    out = Path.expand("avm_deps/elixir_process.avm")
    beam_path = Path.join(System.tmp_dir!(), "Elixir.Process.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "process_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule Process do
      @moduledoc false
      @compile {:autoload, false}

      defdelegate alive?(pid), to: :erlang, as: :is_process_alive

      def sleep(timeout) when is_integer(timeout) and timeout >= 0 or timeout == :infinity do
        receive do
        after
          timeout -> :ok
        end
      end

      def send(dest, msg, options) when is_list(options) do
        case :erlang.send(dest, msg, options) do
          :ok -> :ok
          :noconnect -> :noconnect
          :nosuspend -> :nosuspend
        end
      end

      def exit(pid, reason) do
        :erlang.exit(pid, reason)
        true
      end

      def spawn(fun) when is_function(fun, 0), do: :erlang.spawn(fun)
      def spawn(module, fun, args), do: :erlang.spawn(module, fun, args)
      def spawn_link(fun) when is_function(fun, 0), do: :erlang.spawn_link(fun)
      def spawn_link(module, fun, args), do: :erlang.spawn_link(module, fun, args)
      def spawn_monitor(fun) when is_function(fun, 0), do: :erlang.spawn_monitor(fun)
      def spawn_monitor(module, fun, args), do: :erlang.spawn_monitor(module, fun, args)

      def link(pid_or_port), do: :erlang.link(pid_or_port)
      def unlink(pid_or_port), do: :erlang.unlink(pid_or_port)

      def monitor(item), do: :erlang.monitor(:process, item)
      def monitor(item, opts) when is_list(opts), do: :erlang.monitor(:process, item, opts)

      def demonitor(monitor_ref, options \\\\ []) do
        :erlang.demonitor(monitor_ref, options)
      end

      def register(pid_or_port, name) when is_atom(name) do
        :erlang.register(name, pid_or_port)
      end

      def unregister(name) when is_atom(name), do: :erlang.unregister(name)

      def whereis(name), do: nillify(:erlang.whereis(name))

      defdelegate flag(flag, value), to: :erlang, as: :process_flag
      defdelegate flag(pid, flag, value), to: :erlang, as: :process_flag

      def info(pid), do: nillify(:erlang.process_info(pid))

      def info(pid, :registered_name) do
        case :erlang.process_info(pid, :registered_name) do
          :undefined -> nil
          [] -> {:registered_name, []}
          other -> other
        end
      end

      def info(pid, spec) when is_atom(spec) or is_list(spec) do
        nillify(:erlang.process_info(pid, spec))
      end

      def put(key, value), do: nillify(:erlang.put(key, value))

      def get(key, default \\\\ nil) do
        case :erlang.get(key) do
          :undefined -> default
          value -> value
        end
      end

      def delete(key), do: nillify(:erlang.erase(key))

      defp nillify(:undefined), do: nil
      defp nillify(other), do: other
    end
    """)

    compile_stub!(stub_ex, beam_path, Process)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    File.cp!(beam_path, Path.join(Mix.Project.compile_path(), "Elixir.Process.beam"))
    Mix.shell().info("Wrote AtomVM Process stub -> #{out} (and app ebin)")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # AtomVM List has no keystore/4 (Plug.Conn.put_resp_header needs it).
  # Read stock AtomVM List.ex (do not edit AtomVM) and pack a copy with keystore.
  def write_list_avm!(output) do
    out = Path.expand(output)
    compile_path = Mix.Project.compile_path()
    beam_path = Path.join(System.tmp_dir!(), "Elixir.List.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "list_atomvm_stub.ex")

    list_src =
      [
        Path.expand("../../../../AtomVM/libs/exavmlib/lib/List.ex", __DIR__),
        Path.expand("../AtomVM/libs/exavmlib/lib/List.ex", File.cwd!()),
        Path.expand("../../AtomVM/libs/exavmlib/lib/List.ex", File.cwd!()),
        Path.expand("../../../AtomVM/libs/exavmlib/lib/List.ex", File.cwd!()),
        "/home/linsei/Work/ElixirChip/AtomVM/libs/exavmlib/lib/List.ex"
      ]
      |> Enum.find(&File.exists?/1)

    unless list_src do
      Mix.raise("AtomVM List.ex not found; cannot build List.keystore stub")
    else
      source = File.read!(list_src)

      insert = """

        @doc false
        @spec keystore([tuple], any, non_neg_integer, tuple) :: [tuple]
        def keystore(list, key, position, new_tuple)
            when is_list(list) and is_integer(position) and position >= 0 and is_tuple(new_tuple) do
          :lists.keystore(key, position + 1, list, new_tuple)
        end
      """

      # Insert after keyfind/4 body (before keymember? docs).
      patched =
        String.replace(
          source,
          ~r/(def keyfind\(list, key, position, default \\\\ nil\) do\n    :lists\.keyfind\(key, position \+ 1, list\) \|\| default\n  end\n)/,
          "\\1#{insert}\n",
          global: false
        )

      if patched == source do
        Mix.raise("Failed to patch AtomVM List.ex for keystore")
      else
        File.write!(stub_ex, patched)

        {_, 0} =
          System.cmd(
            "elixir",
            [
              "-e",
              """
              Code.put_compiler_option(:ignore_module_conflict, true)
              [{List, bytecode}] = Code.compile_file(#{inspect(stub_ex)})
              File.write!(#{inspect(beam_path)}, bytecode)
              """
            ],
            stderr_to_stdout: true
          )

        ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
        File.cp!(beam_path, Path.join(compile_path, "Elixir.List.beam"))
        Mix.shell().info("Wrote AtomVM List+keystore stub -> #{out} (and app ebin)")
        File.rm(beam_path)
        File.rm(stub_ex)
        :ok
      end
    end
  end

  # AtomVM Enum lacks map_reduce/3, unzip/1, reverse/2 used by Ecto.Query.Planner.
  defp write_enum_avm! do
    out = Path.expand("avm_deps/elixir_enum.avm")
    compile_path = Mix.Project.compile_path()
    beam_path = Path.join(System.tmp_dir!(), "Elixir.Enum.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "enum_atomvm_stub.ex")

    enum_src =
      [
        Path.expand("../../../../AtomVM/libs/exavmlib/lib/Enum.ex", __DIR__),
        Path.expand("../../AtomVM/libs/exavmlib/lib/Enum.ex", File.cwd!()),
        Path.expand("../../../AtomVM/libs/exavmlib/lib/Enum.ex", File.cwd!()),
        "/home/linsei/Work/ElixirChip/AtomVM/libs/exavmlib/lib/Enum.ex"
      ]
      |> Enum.find(&File.exists?/1)

    unless enum_src do
      Mix.shell().error("AtomVM Enum.ex not found; skipping Enum extras stub")
      :ok
    else
      source = File.read!(enum_src)

      insert = """

        @doc false
        @spec map_reduce(t, any, (element, any -> {element, any})) :: {list, any}
        def map_reduce(enumerable, acc, fun) when is_list(enumerable) do
          :lists.mapfoldl(fun, acc, enumerable)
        end

        def map_reduce(enumerable, acc, fun) do
          {list, acc} =
            reduce(enumerable, {[], acc}, fn entry, {list, acc} ->
              {new_entry, acc} = fun.(entry, acc)
              {[new_entry | list], acc}
            end)

          {:lists.reverse(list), acc}
        end

        @doc false
        @spec unzip(t) :: {list, list}
        def unzip(enumerable) when is_list(enumerable) do
          unzip_list(:lists.reverse(enumerable), [], [])
        end

        def unzip(enumerable) do
          unzip_list(reverse(enumerable), [], [])
        end

        defp unzip_list([], acc1, acc2), do: {acc1, acc2}

        defp unzip_list([{el1, el2} | rest], acc1, acc2) do
          unzip_list(rest, [el1 | acc1], [el2 | acc2])
        end

        @doc false
        @spec reverse(t, t) :: list
        def reverse(enumerable, tail) when is_list(enumerable) do
          :lists.reverse(enumerable, to_list(tail))
        end

        def reverse(enumerable, tail) do
          reduce(enumerable, to_list(tail), fn entry, acc -> [entry | acc] end)
        end

        @doc false
        @spec zip(t, t) :: list
        def zip(list1, list2) when is_list(list1) and is_list(list2) do
          zip_lists(list1, list2)
        end

        def zip(enumerable1, enumerable2) do
          zip_lists(to_list(enumerable1), to_list(enumerable2))
        end

        defp zip_lists([a | as], [b | bs]), do: [{a, b} | zip_lists(as, bs)]
        defp zip_lists(_, _), do: []

        @doc false
        def map_intersperse(enumerable, separator, mapper) when is_list(enumerable) do
          map_intersperse_list(enumerable, separator, mapper)
        end

        def map_intersperse(enumerable, separator, mapper) do
          map_intersperse_list(to_list(enumerable), separator, mapper)
        end

        defp map_intersperse_list([], _separator, _mapper), do: []
        defp map_intersperse_list([h], _separator, mapper), do: [mapper.(h)]

        defp map_intersperse_list([h | t], separator, mapper) do
          [mapper.(h), separator | map_intersperse_list(t, separator, mapper)]
        end

        @doc false
        @spec sort_by(t, (element -> any)) :: list
        def sort_by(enumerable, mapper) when is_function(mapper, 1) do
          mapped =
            Enum.map(enumerable, fn entry ->
              {mapper.(entry), entry}
            end)

          # Prefer :lists.sort/2 over :lists.keysort/2 (ExAtomVM may warn on keysort).
          sorted = :lists.sort(fn {a, _}, {b, _} -> a <= b end, mapped)
          Enum.map(sorted, fn {_key, entry} -> entry end)
        end
      """

      patched =
        String.replace(
          source,
          ~r/(def map\(enumerable, fun\) do\n    reduce\(enumerable, \[\], R\.map\(fun\)\) \|> :lists\.reverse\(\)\n  end\n)/,
          "\\1#{insert}\n",
          global: false
        )

      if patched == source do
        Mix.shell().error("Failed to patch AtomVM Enum.ex for extras; skipping")
        :ok
      else
        File.write!(stub_ex, patched)

        {output, status} =
          System.cmd(
            "elixir",
            [
              "-e",
              """
              Code.put_compiler_option(:ignore_module_conflict, true)
              [{Enum, bytecode}] = Code.compile_file(#{inspect(stub_ex)})
              File.write!(#{inspect(beam_path)}, bytecode)
              """
            ],
            stderr_to_stdout: true
          )

        if status != 0 do
          Mix.shell().error("Enum stub compile failed:\n#{output}")
          :ok
        else
          ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
          File.cp!(beam_path, Path.join(compile_path, "Elixir.Enum.beam"))
          Mix.shell().info("Wrote AtomVM Enum extras stub -> #{out} (and app ebin)")
          File.rm(beam_path)
          File.rm(stub_ex)
          :ok
        end
      end
    end
  end

  # AtomVM Map lacks update!/3 and drop/2 (Ecto.Query.Planner / Changeset).
  defp write_map_avm! do
    out = Path.expand("avm_deps/elixir_map.avm")
    compile_path = Mix.Project.compile_path()
    beam_path = Path.join(System.tmp_dir!(), "Elixir.Map.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "map_atomvm_stub.ex")

    map_src =
      [
        Path.expand("../../../../AtomVM/libs/exavmlib/lib/Map.ex", __DIR__),
        Path.expand("../AtomVM/libs/exavmlib/lib/Map.ex", File.cwd!()),
        Path.expand("../../AtomVM/libs/exavmlib/lib/Map.ex", File.cwd!()),
        Path.expand("../../../AtomVM/libs/exavmlib/lib/Map.ex", File.cwd!()),
        "/home/linsei/Work/ElixirChip/AtomVM/libs/exavmlib/lib/Map.ex"
      ]
      |> Enum.find(&File.exists?/1)

    unless map_src do
      Mix.raise("AtomVM Map.ex not found; cannot build Map compatibility AVM")
    else
      source = File.read!(map_src)

      insert = """

        @doc false
        def get_and_update!(map, key, fun) when is_function(fun, 1) do
          value = :maps.get(key, map)

          case fun.(value) do
            {get, update} -> {get, :maps.put(key, update, map)}
            :pop -> {value, :maps.remove(key, map)}
            other ->
              raise "the given function must return a two-element tuple or :pop, got: \#{inspect(other)}"
          end
        end

        @doc false
        def update!(%{} = map, key, fun) when is_function(fun, 1) do
          case map do
            %{^key => value} -> %{map | key => fun.(value)}
            %{} -> :erlang.error({:badkey, key}, [map, key])
          end
        end

        @doc false
        def drop(%{} = map, keys) when is_list(keys) do
          :lists.foldl(fn key, acc -> :maps.remove(key, acc) end, map, keys)
        end

        @doc false
        def take(%{} = map, keys) when is_list(keys) do
          :lists.foldl(
            fn key, acc ->
              case :maps.find(key, map) do
                {:ok, value} -> :maps.put(key, value, acc)
                :error -> acc
              end
            end,
            %{},
            keys
          )
        end
      """

      patched =
        String.replace(
          source,
          ~r/(def put\(map, key, value\) do\n    :maps\.put\(key, value, map\)\n  end\n)/,
          "\\1#{insert}\n",
          global: false
        )

      if patched == source do
        Mix.raise("Failed to patch AtomVM Map.ex for compatibility AVM")
      else
        File.write!(stub_ex, patched)

        {output, status} =
          System.cmd(
            "elixir",
            [
              "-e",
              """
              Code.put_compiler_option(:ignore_module_conflict, true)
              [{Map, bytecode}] = Code.compile_file(#{inspect(stub_ex)})
              File.write!(#{inspect(beam_path)}, bytecode)
              """
            ],
            stderr_to_stdout: true
          )

        if status != 0 do
          Mix.raise("Map stub compile failed:\n#{output}")
        else
          ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
          File.cp!(beam_path, Path.join(compile_path, "Elixir.Map.beam"))
          Mix.shell().info("Wrote AtomVM Map.update!/drop stub -> #{out} (and app ebin)")
          File.rm(beam_path)
          File.rm(stub_ex)
          :ok
        end
      end
    end
  end

  defp write_access_avm! do
    source_path =
      [
        Path.expand("../../../../AtomVM/libs/exavmlib/lib/Access.ex", __DIR__),
        Path.expand("../AtomVM/libs/exavmlib/lib/Access.ex", File.cwd!()),
        Path.expand("../../AtomVM/libs/exavmlib/lib/Access.ex", File.cwd!()),
        Path.expand("../../../AtomVM/libs/exavmlib/lib/Access.ex", File.cwd!()),
        "/home/linsei/Work/ElixirChip/AtomVM/libs/exavmlib/lib/Access.ex"
      ]
      |> Enum.find(&File.exists?/1)

    if is_nil(source_path), do: Mix.raise("AtomVM Access.ex not found")

    insert = ~S"""

      def get_and_update(%{} = map, key, fun) when is_function(fun, 1) do
        value = case :maps.find(key, map) do
          {:ok, found} -> found
          :error -> nil
        end

        case fun.(value) do
          {get, update} -> {get, :maps.put(key, update, map)}
          :pop -> {value, :maps.remove(key, map)}
          other -> raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
        end
      end

      def get_and_update(list, key, fun) when is_list(list) and is_atom(key) and is_function(fun, 1) do
        case :lists.keyfind(key, 1, list) do
          {_, value} ->
            case fun.(value) do
              {get, update} -> {get, :lists.keyreplace(key, 1, list, {key, update})}
              :pop -> {value, :lists.keydelete(key, 1, list)}
              other -> raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
            end

          false ->
            case fun.(nil) do
              {get, update} -> {get, [{key, update} | list]}
              :pop -> {nil, list}
              other -> raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
            end
        end
      end

      def get_and_update(nil, key, _fun) do
        raise ArgumentError, "could not put/update key #{inspect(key)} on a nil value"
      end

      def get_and_update(list, key, _fun) when is_list(list) do
        raise ArgumentError, "the Access calls for keywords expect the key to be an atom, got: " <> inspect(key)
      end
    """

    source = File.read!(source_path)
    patched = String.replace(source, "\nend\n", insert <> "\nend\n", global: false)
    if patched == source, do: Mix.raise("Failed to patch AtomVM Access.ex")

    build_dir =
      Path.join(Mix.Project.build_path(), "atomvm_access_#{System.unique_integer([:positive])}")

    File.mkdir_p!(build_dir)

    try do
      patched_path = Path.join(build_dir, "access.ex")
      File.write!(patched_path, patched)

      {message, status} =
        System.cmd("elixirc", ["--ignore-module-conflict", "-o", build_dir, patched_path],
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise(message)

      beam = Path.join(build_dir, "Elixir.Access.beam")
      ExAtomVM.PackBEAM.make_avm([{beam, :beam}], "avm_deps/elixir_access.avm")
      File.cp!(beam, Path.join(Mix.Project.compile_path(), "Elixir.Access.beam"))
      :ok
    after
      File.rm_rf!(build_dir)
    end
  end

  # AtomVM :application has get_env/2,3 but not get_application/1.
  # Exception.format_application/1 needs it; missing import makes Exception look undef.
  defp write_erlang_application_avm! do
    out = Path.expand("avm_deps/erlang_application.avm")
    compile_path = Mix.Project.compile_path()
    beam_path = Path.join(System.tmp_dir!(), "application.atomvm_stub.beam")
    stub_ex = Path.join(System.tmp_dir!(), "erlang_application_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule :application do
      @moduledoc false
      @compile {:autoload, false}

      def get_env(app, key), do: get_env(app, key, :undefined)

      def get_env(_app, _key, default), do: default

      def get_application(_module), do: :undefined
    end
    """)

    compile_stub!(stub_ex, beam_path, :application)
    ExAtomVM.PackBEAM.make_avm([{beam_path, :beam}], out)
    File.cp!(beam_path, Path.join(compile_path, "application.beam"))
    Mix.shell().info("Wrote AtomVM :application stub -> #{out} (and app ebin)")
    File.rm(beam_path)
    File.rm(stub_ex)
    :ok
  end

  # Connection/Logger paths may need Kernel.Utils; AtomVM ships none.
  # Host Elixir.String is large and may use opcodes AtomVM rejects — ship a stub.
  # Do not compile or patch AtomVM/exavmlib sources here.
  def write_elixir_stdlib_avm! do
    out = Path.expand("avm_deps/elixir_stdlib_extras.avm")
    elixir_ebin = Path.join(:code.lib_dir(:elixir), "ebin")
    compile_path = Mix.Project.compile_path()

    utils = Path.join(elixir_ebin, "Elixir.Kernel.Utils.beam")
    File.cp!(utils, Path.join(compile_path, "Elixir.Kernel.Utils.beam"))

    string_beam = Path.join(System.tmp_dir!(), "Elixir.String.atomvm_stub.beam")
    string_ex = Path.join(System.tmp_dir!(), "string_atomvm_stub.ex")

    File.write!(string_ex, """
    defmodule String do
      @moduledoc false
      @compile {:autoload, false}

      def to_charlist(bin) when is_binary(bin), do: :erlang.binary_to_list(bin)
      def to_integer(bin) when is_binary(bin), do: :erlang.binary_to_integer(bin)
      def to_atom(bin) when is_binary(bin), do: :erlang.binary_to_atom(bin, :utf8)

      def upcase(bin, :ascii) when is_binary(bin), do: upcase_ascii(bin, [])

      defp upcase_ascii(<<>>, acc), do: :erlang.iolist_to_binary(:lists.reverse(acc))
      defp upcase_ascii(<<char, rest::binary>>, acc) when char in ?a..?z,
        do: upcase_ascii(rest, [<<char - 32>> | acc])
      defp upcase_ascii(<<char, rest::binary>>, acc), do: upcase_ascii(rest, [<<char>> | acc])

      def contains?(subject, pattern)
          when is_binary(subject) and is_binary(pattern) do
        :binary.match(subject, pattern) != :nomatch
      end

      def split(subject, pattern, opts \\\\ [])

      def split(subject, pattern, opts)
          when is_binary(subject) and is_binary(pattern) and is_list(opts) do
        case Keyword.get(opts, :parts, :infinity) do
          :infinity ->
            :binary.split(subject, pattern, [:global])

          2 ->
            case :binary.split(subject, pattern, []) do
              [a, b] -> [a, b]
              other -> other
            end

          n when is_integer(n) and n > 2 ->
            split_n(subject, pattern, n, [])

          _ ->
            :binary.split(subject, pattern, [:global])
        end
      end

      def split_n(_subject, _pattern, 1, acc), do: :lists.reverse(acc)

      def split_n(subject, pattern, n, acc) when n > 1 do
        case :binary.split(subject, pattern, []) do
          [part] ->
            :lists.reverse([part | acc])

          [part, rest] ->
            split_n(rest, pattern, n - 1, [part | acc])
        end
      end

      # Ecto.Type.trim/2 uses String.trim_leading/1 for cast.
      def trim_leading(subject) when is_binary(subject) do
        trim_leading_ws(subject)
      end

      defp trim_leading_ws(<<" ", rest::binary>>), do: trim_leading_ws(rest)
      defp trim_leading_ws(<<"\\t", rest::binary>>), do: trim_leading_ws(rest)
      defp trim_leading_ws(<<"\\n", rest::binary>>), do: trim_leading_ws(rest)
      defp trim_leading_ws(<<"\\r", rest::binary>>), do: trim_leading_ws(rest)
      defp trim_leading_ws(other), do: other

      def trim_trailing(subject, trailing)
          when is_binary(subject) and is_binary(trailing) do
        trim_trailing_loop(subject, trailing)
      end

      def trim_trailing_loop(subject, trailing) do
        tsize = byte_size(trailing)
        ssize = byte_size(subject)

        if tsize > 0 and ssize >= tsize and
             :binary.part(subject, ssize - tsize, tsize) == trailing do
          trim_trailing_loop(:binary.part(subject, 0, ssize - tsize), trailing)
        else
          subject
        end
      end

      def pad_leading(subject, count, padding \\\\ " ")

      def pad_leading(subject, count, padding)
          when is_binary(subject) and is_integer(count) and is_binary(padding) do
        len = byte_size(subject)

        if len >= count do
          subject
        else
          :erlang.iolist_to_binary([:binary.copy(padding, count - len), subject])
        end
      end

      def replace(subject, pattern, replacement)
          when is_binary(subject) and is_binary(pattern) and is_binary(replacement) do
        :binary.replace(subject, pattern, replacement, [:global])
      end
    end
    """)

    compile_stub!(string_ex, string_beam, String)
    File.cp!(string_beam, Path.join(compile_path, "Elixir.String.beam"))

    path_beam = Path.join(System.tmp_dir!(), "Elixir.Path.atomvm_stub.beam")
    path_ex = Path.join(System.tmp_dir!(), "path_atomvm_stub.ex")
    File.write!(path_ex, path_stub_source())
    compile_stub!(path_ex, path_beam, Path)
    File.cp!(path_beam, Path.join(compile_path, "Elixir.Path.beam"))

    ExAtomVM.PackBEAM.make_avm(
      [{utils, :beam}, {string_beam, :beam}, {path_beam, :beam}],
      out
    )

    Mix.shell().info("Wrote AtomVM Elixir stdlib extras -> #{out} (and app ebin)")
    File.rm(string_beam)
    File.rm(string_ex)
    File.rm(path_beam)
    File.rm(path_ex)
    :ok
  end

  def path_stub_source do
    ~S'''
    defmodule Path do
      @moduledoc false
      @compile {:autoload, false}

      def join(paths) when is_list(paths) do
        case paths do
          [name1, name2 | rest] -> join([join(name1, name2) | rest])
          [name] -> name
        end
      end

      def join(left, right) do
        left
        |> do_join(right)
        |> remove_dir_sep()
      end

      defp do_join(left, "/"), do: remove_dir_sep(left)
      defp do_join("", right), do: relative(right)
      defp do_join("/", right), do: "/" <> relative(right)

      defp do_join(left, right), do: remove_dir_sep(left) <> "/" <> relative(right)

      defp relative("/"), do: "."
      defp relative("/" <> rest), do: rest
      defp relative(other), do: other

      defp remove_dir_sep(""), do: ""
      defp remove_dir_sep("/"), do: "/"

      defp remove_dir_sep(bin) do
        size = byte_size(bin)

        if :binary.at(bin, size - 1) == ?/ do
          binary_part(bin, 0, size - 1)
        else
          bin
        end
      end

      def split(path) do
        case :binary.split(path, "/", [:global]) do
          ["" | rest] when rest != [] -> ["/" | reject_empty(rest)]
          other -> reject_empty(other)
        end
      end

      defp reject_empty(list), do: reject_loop(list, [])

      defp reject_loop([], acc), do: :lists.reverse(acc)
      defp reject_loop(["" | tail], acc), do: reject_loop(tail, acc)
      defp reject_loop([head | tail], acc), do: reject_loop(tail, [head | acc])

      def dirname(path) do
        parts = dirname_parts(:binary.split(path, "/", [:global]))
        dirjoin(parts, if(parts == [], do: ".", else: ""))
      end

      defp dirname_parts([]), do: []

      defp dirname_parts(parts) do
        case :lists.reverse(parts) do
          [] -> []
          [_ | tail] -> :lists.reverse(fstrip(tail))
        end
      end

      defp fstrip(["" | [_ | _] = tail]), do: fstrip(tail)
      defp fstrip(list), do: list

      defp dirjoin(["" | tail], acc), do: dirjoin1(tail, acc <> "/")
      defp dirjoin(parts, acc), do: dirjoin1(parts, acc)

      defp dirjoin1([], acc), do: acc
      defp dirjoin1([one], acc), do: acc <> one
      defp dirjoin1([head | tail], acc), do: dirjoin(tail, acc <> head <> "/")

      def basename(name), do: last_non_empty(:binary.split(name, "/", [:global]), "")

      defp last_non_empty([], acc), do: acc
      defp last_non_empty(["" | tail], acc), do: last_non_empty(tail, acc)
      defp last_non_empty([head | tail], _acc), do: last_non_empty(tail, head)

      def basename(name, ext) do
        bname = basename(name)
        le = byte_size(ext)
        pos = byte_size(bname) - le

        if pos < 0 do
          bname
        else
          start = byte_size(name) - pos - le
          slice = binary_part(name, start, pos + le)

          if binary_part(slice, pos, le) == ext do
            binary_part(slice, 0, pos)
          else
            bname
          end
        end
      end

      def rootname(path), do: rootname_scan(path, "", "")

      defp rootname_scan(<<>>, root, _ext), do: reverse_bin(root)

      defp rootname_scan(<<?/, rest::binary>>, root, ext),
        do: rootname_scan(rest, "/" <> ext <> root, "")

      defp rootname_scan(<<?., rest::binary>>, "/" <> _ = root, ""),
        do: rootname_scan(rest, "." <> root, "")

      defp rootname_scan(<<?., rest::binary>>, root, ext),
        do: rootname_scan(rest, ext <> root, ".")

      defp rootname_scan(<<char, rest::binary>>, root, "") when char != ?/ and char != ?.,
        do: rootname_scan(rest, <<char>> <> root, "")

      defp rootname_scan(<<char, rest::binary>>, root, ext) when char != ?/ and char != ?.,
        do: rootname_scan(rest, root, <<char>> <> ext)

      def rootname(path, ext), do: rootname_strip(path, ext, "")

      defp rootname_strip(first, ext, result) when first == ext do
        case result do
          "/" <> _ -> reverse_bin(result) <> ext
          _ -> reverse_bin(result)
        end
      end

      defp rootname_strip(<<>>, _ext, result), do: reverse_bin(result)

      defp rootname_strip(<<char, rest::binary>>, ext, result),
        do: rootname_strip(rest, ext, <<char>> <> result)

      def extname(name) do
        pos = last_dot(name, 0, -1)

        cond do
          pos < 0 ->
            ""

          pos == 0 ->
            ""

          true ->
            part = binary_part(name, pos - 1, byte_size(name) - pos + 1)

            if :binary.match(part, "/") == :nomatch do
              binary_part(name, pos, byte_size(name) - pos)
            else
              ""
            end
        end
      end

      defp last_dot(bin, index, best) do
        if index >= byte_size(bin) do
          best
        else
          best = if :binary.at(bin, index) == ?., do: index, else: best
          last_dot(bin, index + 1, best)
        end
      end

      defp reverse_bin(bin), do: reverse_loop(bin, "")
      defp reverse_loop(<<>>, acc), do: acc
      defp reverse_loop(<<char, rest::binary>>, acc), do: reverse_loop(rest, <<char>> <> acc)
    end
    '''
  end

  # Posts timestamps need NaiveDateTime/DateTime; AtomVM ships neither.
  defp write_calendar_avm! do
    out = Path.expand("avm_deps/elixir_calendar.avm")
    compile_path = Mix.Project.compile_path()
    stub_ex = Path.join(System.tmp_dir!(), "calendar_atomvm_stub.ex")

    File.write!(stub_ex, """
    defmodule Calendar.ISO do
      @moduledoc false
      @compile {:autoload, false}
    end

    defmodule Calendar do
      @moduledoc false
      @compile {:autoload, false}
    end

    defmodule NaiveDateTime do
      @moduledoc false
      @compile {:autoload, false}

      defstruct year: 0,
                month: 1,
                day: 1,
                hour: 0,
                minute: 0,
                second: 0,
                microsecond: {0, 0},
                calendar: Calendar.ISO

      def to_gregorian_seconds(
            %{
              year: y,
              month: m,
              day: d,
              hour: h,
              minute: min,
              second: s,
              microsecond: {us, _}
            }
          ) do
        # Accept NaiveDateTime and DateTime maps — Postgrex.Extensions.Timestamp
        # passes either into this helper.
        secs = :calendar.datetime_to_gregorian_seconds({{y, m, d}, {h, min, s}})
        {secs, us}
      end

      def from_gregorian_seconds(seconds, {microsecond, precision} \\\\ {0, 0})
          when is_integer(seconds) do
        {date, time} = gregorian_seconds_to_datetime(seconds)

        %NaiveDateTime{
          year: elem(date, 0),
          month: elem(date, 1),
          day: elem(date, 2),
          hour: elem(time, 0),
          minute: elem(time, 1),
          second: elem(time, 2),
          microsecond: {microsecond, precision},
          calendar: Calendar.ISO
        }
      end

      def utc_now do
        # AtomVM accepts only atom time units (not integer multipliers like 1000).
        {{y, mo, d}, {h, mi, s}} = :erlang.universaltime()

        %NaiveDateTime{
          year: y,
          month: mo,
          day: d,
          hour: h,
          minute: mi,
          second: s,
          microsecond: {0, 6},
          calendar: Calendar.ISO
        }
      end

      defp gregorian_seconds_to_datetime(seconds) do
        days = div(seconds, 86400)
        rem_secs = rem(seconds, 86400)

        {days, rem_secs} =
          if rem_secs < 0 do
            {days - 1, rem_secs + 86400}
          else
            {days, rem_secs}
          end

        {gregorian_days_to_date(days),
         {div(rem_secs, 3600), rem(div(rem_secs, 60), 60), rem(rem_secs, 60)}}
      end

      # Inverse of AtomVM calendar:date_to_gregorian_days/3 (Hinnant civil_from_days).
      defp gregorian_days_to_date(z) do
        z = z - 60
        era = if z >= 0, do: div(z, 146097), else: div(z - 146096, 146097)
        doe = z - era * 146097
        yoe = div(doe - div(doe, 1460) + div(doe, 36524) - div(doe, 146096), 365)
        y = yoe + era * 400
        doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
        mp = div(5 * doy + 2, 153)
        d = doy - div(153 * mp + 2, 5) + 1
        m = if mp < 10, do: mp + 3, else: mp - 9
        y = if m <= 2, do: y + 1, else: y
        {y, m, d}
      end
    end

    defmodule DateTime do
      @moduledoc false
      @compile {:autoload, false}

      defstruct year: 0,
                month: 1,
                day: 1,
                hour: 0,
                minute: 0,
                second: 0,
                microsecond: {0, 0},
                utc_offset: 0,
                std_offset: 0,
                time_zone: "Etc/UTC",
                zone_abbr: "UTC",
                calendar: Calendar.ISO

      def from_gregorian_seconds(seconds, {microsecond, precision} \\\\ {0, 0})
          when is_integer(seconds) do
        ndt = NaiveDateTime.from_gregorian_seconds(seconds, {microsecond, precision})
        from_naive!(ndt, "Etc/UTC")
      end

      def from_naive!(%NaiveDateTime{} = ndt, "Etc/UTC") do
        %DateTime{
          year: ndt.year,
          month: ndt.month,
          day: ndt.day,
          hour: ndt.hour,
          minute: ndt.minute,
          second: ndt.second,
          microsecond: ndt.microsecond,
          utc_offset: 0,
          std_offset: 0,
          time_zone: "Etc/UTC",
          zone_abbr: "UTC",
          calendar: Calendar.ISO
        }
      end

      def from_naive!(%NaiveDateTime{} = ndt, "UTC"), do: from_naive!(ndt, "Etc/UTC")

      def utc_now do
        from_naive!(NaiveDateTime.utc_now(), "Etc/UTC")
      end

      def to_unix(%DateTime{} = dt, unit) do
        ndt = %NaiveDateTime{
          year: dt.year,
          month: dt.month,
          day: dt.day,
          hour: dt.hour,
          minute: dt.minute,
          second: dt.second,
          microsecond: dt.microsecond,
          calendar: Calendar.ISO
        }

        {secs, us} = NaiveDateTime.to_gregorian_seconds(ndt)
        # Unix epoch is 62167219200 gregorian seconds.
        unix_secs = secs - 62_167_219_200

        case unit do
          :second -> unix_secs
          :millisecond -> unix_secs * 1_000 + div(us, 1_000)
          :microsecond -> unix_secs * 1_000_000 + us
          :nanosecond -> unix_secs * 1_000_000_000 + us * 1_000
        end
      end
    end
    """)

    {output, status} =
      System.cmd(
        "elixir",
        [
          "-e",
          """
          Code.put_compiler_option(:ignore_module_conflict, true)
          compiled = Code.compile_file(#{inspect(stub_ex)})
          Enum.each(compiled, fn {mod, bytecode} ->
            path = Path.join(#{inspect(System.tmp_dir!())}, Atom.to_string(mod) <> ".beam")
            File.write!(path, bytecode)
            IO.puts(path)
          end)
          """
        ],
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.shell().error("Calendar stub compile failed:\n#{output}")
      :ok
    else
      beams =
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.ends_with?(&1, ".beam"))
        |> Enum.map(fn path ->
          File.cp!(path, Path.join(compile_path, Path.basename(path)))
          {path, :beam}
        end)

      ExAtomVM.PackBEAM.make_avm(beams, out)
      Mix.shell().info("Wrote AtomVM Calendar stubs -> #{out} (and app ebin)")
      Enum.each(beams, fn {path, _} -> File.rm(path) end)
      File.rm(stub_ex)
      :ok
    end
  end

  defp compile_stub!(stub_ex, beam_path, module) do
    {_, 0} =
      System.cmd(
        "elixir",
        [
          "-e",
          """
          Code.put_compiler_option(:ignore_module_conflict, true)
          [{#{inspect(module)}, bytecode}] = Code.compile_file(#{inspect(stub_ex)})
          File.write!(#{inspect(beam_path)}, bytecode)
          """
        ],
        stderr_to_stdout: true
      )

    :ok
  end
end

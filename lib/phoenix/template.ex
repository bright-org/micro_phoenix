defmodule Phoenix.Template do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      import Phoenix.Template, only: [embed_templates: 1, embed_templates: 2]
      @phoenix_template_format Keyword.get(unquote(opts), :format, "heex")
    end
  end

  defmacro embed_templates(pattern, _opts \\ []) do
    caller_file = __CALLER__.file
    root = Path.dirname(caller_file)
    pattern = Path.join(root, pattern)
    files = Path.wildcard(pattern)

    definitions =
      for file <- files do
        name =
          file
          |> Path.basename()
          |> Path.rootname(".heex")
          |> Path.rootname(".html")
          |> String.to_atom()

        compiled = compile_heex(file)

        quote do
          def unquote(name)(assigns) do
            var!(assigns) = Map.new(assigns)
            unquote(compiled)
          end
        end
      end

    quote do
      unquote_splicing(definitions)
    end
  end

  def compile_heex(path) do
    source = File.read!(path)
    eex_source = heex_to_eex(source)

    EEx.compile_string(eex_source, line: 1, file: path)
  end

  defp heex_to_eex(source) do
    {source, scripts} = extract_scripts(source)

    converted =
      source
      |> String.replace(~r/<\.live_title[^>]*>\{assigns\[:page_title\]\}<\/\.live_title>/, "<%= live_title(var!(assigns)) %>")
      |> String.replace(~r/<Layouts\.([\w]+)\s+flash=\{@flash\}\s*\/>/, "<%= Layouts.\\1(%{flash: @flash}) %>")
      |> String.replace(~r/<Layouts\.([\w]+)\s*\/>/, "<%= Layouts.\\1(%{}) %>")
      |> String.replace(~r/\{(@[\w.]+)\}/, "<%= \\1 %>")
      |> String.replace(~r/\{(~p"[^"]+")\}/, "<%= \\1 %>")
      |> String.replace(~r/\{(get_csrf_token\(\))\}/, "<%= \\1 %>")
      |> String.replace(~r/\{(assigns\[[^\]]+\])\}/, "<%= \\1 %>")

    restore_scripts(converted, scripts)
  end

  defp extract_scripts(source) do
    scripts = Regex.scan(~r/<script[^>]*>.*?<\/script>/ms, source, capture: :all)

    reduced =
      Enum.reduce(Enum.with_index(scripts), source, fn {[script], idx}, acc ->
        String.replace(acc, script, "<!--SCRIPT#{idx}-->", global: false)
      end)

    script_map =
      scripts
      |> Enum.with_index()
      |> Map.new(fn {[script], idx} -> {"<!--SCRIPT#{idx}-->", script} end)

    {reduced, script_map}
  end

  defp restore_scripts(source, scripts) do
    Enum.reduce(scripts, source, fn {placeholder, script}, acc ->
      String.replace(acc, placeholder, script)
    end)
  end
end

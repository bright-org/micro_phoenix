defmodule Mix.Tasks.Compile.PhoenixLiveView do
  @moduledoc false
  @shortdoc "Compiles HEEx templates (micro_phoenix compatibility)"

  use Mix.Task.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
    Phoenix.LiveView.Compiler.__compile__()
    {:ok, []}
  end

  @impl Mix.Task.Compiler
  def manifests, do: []
end

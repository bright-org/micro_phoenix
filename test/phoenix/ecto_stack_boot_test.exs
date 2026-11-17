defmodule Phoenix.EctoStackBootTest do
  use ExUnit.Case, async: false

  defmodule StartedApp do
    def start(:normal, []), do: {:ok, self()}
  end

  defmodule AlreadyStartedApp do
    def start(:normal, []), do: {:error, {:already_started, self()}}
  end

  defmodule FailingApp do
    def start(:normal, []), do: {:error, :boom}
  end

  test "missing modules are skipped so mini_ecto-only boots continue" do
    assert :ok ==
             Phoenix.AtomVM.ensure_ecto_stack_started([
               NoSuchApp,
               StartedApp,
               AlreadyStartedApp
             ])
  end

  test "an app that fails to start is reported without crashing boot" do
    assert :ok == Phoenix.AtomVM.ensure_ecto_stack_started([FailingApp])
  end
end

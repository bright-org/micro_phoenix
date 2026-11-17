defmodule AtomVM.URI.Error do
  @moduledoc """
  URI validation error for the AtomVM implementation.

  This cannot be the same exception module as Elixir's `URI.Error`, which is
  unavailable in the target runtime.
  """

  defexception action: nil, reason: nil, part: nil

  def exception(opts) when is_list(opts) do
    %__MODULE__{
      action: find_option(opts, :action),
      reason: find_option(opts, :reason),
      part: find_option(opts, :part)
    }
  end

  defp find_option([], _key), do: nil
  defp find_option([{key, value} | _rest], key), do: value
  defp find_option([_ | rest], key), do: find_option(rest, key)

  @impl true
  def message(%__MODULE__{action: action, reason: reason, part: part}) do
    "cannot " <>
      :erlang.atom_to_binary(action) <>
      " due to reason " <>
      :erlang.atom_to_binary(reason) <> ": \"" <> part <> "\""
  end
end

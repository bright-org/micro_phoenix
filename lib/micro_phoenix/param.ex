defmodule MicroPhoenix.Param do
  @moduledoc false

  # AtomVM: avoid Elixir protocols (consolidated impl modules missing at runtime).

  def to_param(int) when is_integer(int), do: :erlang.integer_to_binary(int)
  def to_param(bin) when is_binary(bin), do: bin
  def to_param(atom) when is_atom(atom) and not is_nil(atom), do: Atom.to_string(atom)

  def to_param(%{id: nil}) do
    raise ArgumentError, "cannot convert struct to param, key :id contains a nil value"
  end

  def to_param(%{id: id}), do: to_param(id)

  def to_param(nil) do
    raise ArgumentError, "cannot convert nil to param"
  end

  def to_param(data) do
    raise ArgumentError, "cannot convert #{inspect(data)} to param"
  end
end

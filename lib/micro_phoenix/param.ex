defprotocol MicroPhoenix.Param do
  @moduledoc false
  @fallback_to_any true
  @spec to_param(term) :: String.t()
  def to_param(term)
end

defimpl MicroPhoenix.Param, for: Integer do
  def to_param(int), do: Integer.to_string(int)
end

defimpl MicroPhoenix.Param, for: BitString do
  def to_param(bin) when is_binary(bin), do: bin
end

defimpl MicroPhoenix.Param, for: Atom do
  def to_param(nil), do: raise(ArgumentError, "cannot convert nil to param")
  def to_param(atom), do: Atom.to_string(atom)
end

defimpl MicroPhoenix.Param, for: Any do
  def to_param(%{id: nil}) do
    raise ArgumentError, "cannot convert struct to param, key :id contains a nil value"
  end

  def to_param(%{id: id}) when is_integer(id), do: Integer.to_string(id)
  def to_param(%{id: id}) when is_binary(id), do: id
  def to_param(%{id: id}), do: MicroPhoenix.Param.to_param(id)

  def to_param(data) do
    raise Protocol.UndefinedError, protocol: @protocol, value: data
  end
end

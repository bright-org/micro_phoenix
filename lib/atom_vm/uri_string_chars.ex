defimpl String.Chars, for: AtomVM.URI do
  def to_string(uri), do: AtomVM.URI.to_string(uri)
end

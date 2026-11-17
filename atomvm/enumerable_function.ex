defimpl Enumerable, for: Function do
  def count(_function), do: {:error, __MODULE__}
  def member?(_function, _value), do: {:error, __MODULE__}
  def slice(_function), do: {:error, __MODULE__}

  def reduce(function, acc, fun) when is_function(function, 2), do: function.(acc, fun)

  def reduce(function, _acc, _fun) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: function,
      description: "only anonymous functions of arity 2 are enumerable"
  end
end

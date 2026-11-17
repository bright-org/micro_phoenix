defmodule AtomVM.URI.FunctionEnumerableProbe do
  def start do
    send(self(), {:query, "a=1&b=2"})

    receive do
      {:query, query} ->
        decoder = AtomVM.URI.query_decoder(query)
        [{"a", "1"}, {"b", "2"}] = Enum.to_list(decoder)
        {:error, Enumerable.Function} = Enumerable.count(decoder)
        {:error, Enumerable.Function} = Enumerable.member?(decoder, {"a", "1"})
        {:error, Enumerable.Function} = Enumerable.slice(decoder)

        {:halted, [{"a", "1"}]} =
          Enumerable.reduce(decoder, {:cont, []}, fn pair, _acc -> {:halt, [pair]} end)

        {:suspended, [], continue} =
          Enumerable.reduce(decoder, {:suspend, []}, fn pair, acc -> {:cont, [pair | acc]} end)

        {:done, [{"b", "2"}, {"a", "1"}]} = continue.({:cont, []})
        :erlang.display(:function_enumerable_ok)
    end

    :ok
  end
end

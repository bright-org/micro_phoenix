if Code.ensure_loaded?(Phoenix.HTML) do
  defimpl Phoenix.HTML.FormData, for: Ecto.Changeset do
    def to_form(changeset, opts) do
      %{params: params, data: data, action: action} = changeset
      {action, opts} = Keyword.pop(opts, :action, action)
      {name, opts} = Keyword.pop(opts, :as)

      name = to_string(name || form_for_name(data))
      id = Keyword.get(opts, :id) || name

      %Phoenix.HTML.Form{
        source: changeset,
        impl: __MODULE__,
        id: id,
        action: action,
        name: name,
        errors: form_for_errors(changeset, action),
        data: data,
        params: params || %{},
        hidden: form_for_hidden(data),
        options: Keyword.put_new(opts, :method, form_for_method(data))
      }
    end

    def to_form(_source, _form, _field, _opts), do: []

    def input_value(%{changes: changes, data: data}, %{params: params}, field)
        when is_atom(field) do
      case changes do
        %{^field => value} ->
          value

        %{} ->
          string = Atom.to_string(field)

          case params do
            %{^string => value} -> value
            %{} -> Map.get(data, field)
          end
      end
    end

    def input_value(_data, _form, field) do
      raise ArgumentError, "expected field to be an atom, got: #{inspect(field)}"
    end

    def input_validations(_changeset, _form, _field), do: []

    defp form_for_errors(%{action: nil}, _action), do: []
    defp form_for_errors(%{action: :ignore}, _action), do: []

    defp form_for_errors(%{errors: errors}, _action) do
      Enum.map(errors, fn {field, {msg, opts}} -> {field, {msg, opts}} end)
    end

    defp form_for_errors(_, _), do: []

    defp form_for_name(%{__struct__: module}) do
      module
      |> Atom.to_string()
      |> strip_elixir_prefix()
      |> Phoenix.Binary.split(".")
      |> List.last()
      |> camel_to_snake()
    end

    defp strip_elixir_prefix(<<"Elixir.", rest::binary>>), do: rest
    defp strip_elixir_prefix(other), do: other

    # AtomVM has no Elixir.Macro — minimal camelCase -> snake_case for form names.
    defp camel_to_snake(name) when is_binary(name), do: camel_to_snake(name, <<>>, nil)

    defp camel_to_snake(<<>>, acc, _prev), do: acc

    defp camel_to_snake(<<c, rest::binary>>, acc, prev) when c >= ?A and c <= ?Z do
      lc = c + 32

      need_underscore =
        prev != nil and
          ((prev >= ?a and prev <= ?z) or
             (prev >= ?A and prev <= ?Z and starts_with_lower?(rest)))

      acc = if need_underscore, do: acc <> "_", else: acc
      camel_to_snake(rest, acc <> <<lc>>, c)
    end

    defp camel_to_snake(<<c, rest::binary>>, acc, _prev) do
      camel_to_snake(rest, acc <> <<c>>, c)
    end

    defp starts_with_lower?(<<c, _::binary>>) when c >= ?a and c <= ?z, do: true
    defp starts_with_lower?(_), do: false

    defp form_for_name(_), do: "changeset"

    defp form_for_method(%{__meta__: %{state: :loaded}}), do: "put"
    defp form_for_method(%{id: id}) when not is_nil(id), do: "put"
    defp form_for_method(_), do: "post"

    defp form_for_hidden(%{id: id}) when not is_nil(id), do: [id: id]
    defp form_for_hidden(_), do: []
  end
end

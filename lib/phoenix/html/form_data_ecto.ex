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
      for {field, {msg, opts}} <- errors do
        {field, {msg, opts}}
      end
    end

    defp form_for_errors(_, _), do: []

    defp form_for_name(%{__struct__: module}) do
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    defp form_for_name(_), do: "changeset"

    defp form_for_method(%{__meta__: %{state: :loaded}}), do: "put"
    defp form_for_method(%{id: id}) when not is_nil(id), do: "put"
    defp form_for_method(_), do: "post"

    defp form_for_hidden(%{id: id}) when not is_nil(id), do: [id: id]
    defp form_for_hidden(_), do: []
  end
end

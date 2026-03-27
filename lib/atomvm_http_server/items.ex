defmodule AtomvmHttpServer.Items do
  import Ecto.Query, warn: false

  alias AtomvmHttpServer.Item
  alias AtomvmHttpServer.Repo

  def list_items do
    Repo.all(from(i in Item, order_by: [asc: i.id]))
  end

  def create_item(name) when is_binary(name) do
    create_item(%{name: name})
  end

  def create_item(attrs) when is_map(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def delete_item(id) when is_integer(id) do
    case Repo.get(Item, id) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item)
    end
  end
end

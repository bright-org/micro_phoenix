defmodule MicroPhoenix.TestPageHTML do
  def home(assigns) do
    "<h1>#{assigns.page_title}</h1>"
  end

  def index(assigns) do
    "<ul>#{assigns.posts}</ul>"
  end
end

defmodule MicroPhoenix.TestPageController do
  use MicroPhoenix.Controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "Home")
    |> render(:home)
  end
end

defmodule MicroPhoenix.TestPostHTML do
  def index(assigns), do: "<h1>Posts</h1><p>#{assigns.count}</p>"
  def show(assigns), do: "<p>Post #{assigns.id}</p>"
end

defmodule MicroPhoenix.TestPostController do
  use MicroPhoenix.Controller

  def index(conn, _params) do
    render(conn, :index, count: 2)
  end

  def show(conn, %{"id" => id}) do
    render(conn, :show, id: id)
  end

  def create(conn, %{"post" => %{"title" => title}}) do
    conn
    |> put_flash(:info, "Created #{title}")
    |> redirect(to: "/posts")
  end
end

defmodule MicroPhoenix.TestRouter do
  use MicroPhoenix.Router

  get "/", MicroPhoenix.TestPageController, :home
  resources "/posts", MicroPhoenix.TestPostController
end

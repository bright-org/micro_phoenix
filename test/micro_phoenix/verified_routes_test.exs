defmodule MicroPhoenix.VerifiedRoutesTest do
  use ExUnit.Case, async: true

  defmodule Post, do: defstruct [:id]

  defmodule Routes do
    import MicroPhoenix.VerifiedRoutes, only: [sigil_p: 2]

    use MicroPhoenix.VerifiedRoutes,
      endpoint: MicroPhoenix.VerifiedRoutesTest.Endpoint,
      router: MicroPhoenix.VerifiedRoutesTest.Router,
      statics: ~w(assets)

    defmodule Endpoint do
      def path(path), do: path
    end

    defmodule Router do
      def routes, do: []
    end

    def posts_path, do: ~p"/posts"
    def post_path(post), do: ~p"/posts/#{post}"
    def post_edit_path(post), do: ~p"/posts/#{post}/edit"
    def post_new_path, do: ~p"/posts/new"
  end

  test "static path" do
    assert Routes.posts_path() == "/posts"
    assert Routes.post_new_path() == "/posts/new"
  end

  test "dynamic path with struct id" do
    assert Routes.post_path(%Post{id: 42}) == "/posts/42"
    assert Routes.post_edit_path(%Post{id: 7}) == "/posts/7/edit"
  end

  test "dynamic path with integer" do
    defmodule IntRoutes do
      import MicroPhoenix.VerifiedRoutes, only: [sigil_p: 2]

      use MicroPhoenix.VerifiedRoutes,
        endpoint: MicroPhoenix.VerifiedRoutesTest.Endpoint,
        router: MicroPhoenix.VerifiedRoutesTest.Router

      def show_path(id), do: ~p"/posts/#{id}"
    end

    assert IntRoutes.show_path(3) == "/posts/3"
  end
end

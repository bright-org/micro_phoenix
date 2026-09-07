defmodule MicroPhoenix.RouterTest do
  use ExUnit.Case, async: true

  alias MicroPhoenix.TestRouter, as: Router

  test "GET / renders home" do
    response = Router.dispatch(request(:get, "/"))

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "<h1>Home</h1>"
  end

  test "GET /posts renders index" do
    response = Router.dispatch(request(:get, "/posts"))

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Posts"
  end

  test "GET /posts/:id renders show" do
    response = Router.dispatch(request(:get, "/posts/42"))

    assert response =~ "Post 42"
  end

  test "POST /posts redirects with flash" do
    body = "post[title]=Hello"

    response =
      Router.dispatch(
        request(
          :post,
          "/posts",
          "content-type: application/x-www-form-urlencoded\r\n",
          body
        )
      )

    assert response =~ "HTTP/1.1 302 Found"
    assert response =~ "Location: /posts"
    assert response =~ "Set-Cookie: _micro_flash="
    assert response =~ "Created"
  end

  test "unknown path returns 404" do
    response = Router.dispatch(request(:get, "/missing"))

    assert response =~ "HTTP/1.1 404 Not Found"
  end

  defp request(method, path, extra_headers \\ "", body \\ "") do
    method = method |> Atom.to_string() |> String.upcase()

    """
    #{method} #{path} HTTP/1.1\r
    host: localhost\r
    #{extra_headers}\r
    #{body}
    """
    |> MicroPhoenix.Request.parse()
  end
end

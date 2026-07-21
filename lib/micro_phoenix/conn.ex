defmodule MicroPhoenix.Conn do
  @type t :: %__MODULE__{
          method: atom(),
          path: String.t(),
          params: map(),
          path_params: map(),
          query_params: map(),
          body_params: map(),
          assigns: map(),
          flash: map(),
          status: non_neg_integer(),
          halted: boolean(),
          private: map(),
          resp_body: String.t() | nil,
          resp_content_type: String.t(),
          resp_headers: [{String.t(), String.t()}]
        }

  defstruct method: :get,
            path: "/",
            params: %{},
            path_params: %{},
            query_params: %{},
            body_params: %{},
            assigns: %{},
            flash: %{},
            status: 200,
            halted: false,
            private: %{},
            resp_body: nil,
            resp_content_type: "text/html",
            resp_headers: []

  def from_request(%MicroPhoenix.Request{} = req) do
    %__MODULE__{
      method: req.method,
      path: req.path,
      params: req.params,
      path_params: req.path_params,
      query_params: req.query_params,
      body_params: req.body_params
    }
  end

  def merge_params(%__MODULE__{} = conn) do
    params =
      conn.path_params
      |> Map.merge(conn.query_params)
      |> Map.merge(conn.body_params)

    %{conn | params: params}
  end

end

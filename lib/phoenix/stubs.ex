defmodule Phoenix.Flash do
  @moduledoc false
  def get(flash, key) when is_map(flash), do: Map.get(flash, key)
end

defmodule Phoenix.Channel do
  @moduledoc false
  defmacro __using__(_opts), do: :ok

  def push(%{transport_pid: transport_pid, join_ref: join_ref, topic: topic}, event, payload)
      when is_binary(event) and is_map(payload) do
    send(transport_pid, {:channel_push, join_ref, topic, event, payload})
    :ok
  end

  def broadcast_from(%{pubsub_server: server, topic: topic}, event, payload)
      when not is_nil(server) and is_binary(event) and is_map(payload) do
    Phoenix.PubSub.broadcast_from(
      server,
      self(),
      topic,
      %Phoenix.Socket.Broadcast{topic: topic, event: event, payload: payload}
    )
  end

  def broadcast(%{pubsub_server: server, topic: topic}, event, payload)
      when not is_nil(server) and is_binary(event) and is_map(payload) do
    Phoenix.PubSub.broadcast(
      server,
      topic,
      %Phoenix.Socket.Broadcast{topic: topic, event: event, payload: payload}
    )
  end
end

defmodule Phoenix.PubSub do
  @moduledoc false

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    case :erlang.whereis(name) do
      :undefined ->
        pid = spawn_link(fn -> loop(%{}, %{}) end)
        true = :erlang.register(name, pid)
        {:ok, pid}

      pid ->
        {:error, {:already_started, pid}}
    end
  end

  def subscribe(server, topic), do: call(server, {:subscribe, topic})
  def unsubscribe(server, topic), do: call(server, {:unsubscribe, topic})

  def broadcast(server, topic, message), do: broadcast_from(server, nil, topic, message)

  def broadcast_from(server, sender, topic, message) do
    send(server_pid(server), {:broadcast, sender, topic, message})
    :ok
  end

  defp call(server, request) do
    ref = make_ref()
    send(server_pid(server), {request, self(), ref})

    receive do
      {^ref, response} -> response
    after
      5_000 -> {:error, :timeout}
    end
  end

  defp server_pid(pid) when is_pid(pid), do: pid
  defp server_pid(name), do: :erlang.whereis(name)

  defp loop(topics, monitors) do
    receive do
      {{:subscribe, topic}, pid, ref} ->
        subscribers = Map.get(topics, topic, [])

        {topics, monitors} =
          if :lists.member(pid, subscribers) do
            {topics, monitors}
          else
            monitors =
              if Map.has_key?(monitors, pid) do
                monitors
              else
                Map.put(monitors, pid, :erlang.monitor(:process, pid))
              end

            {Map.put(topics, topic, [pid | subscribers]), monitors}
          end

        send(pid, {ref, :ok})
        loop(topics, monitors)

      {{:unsubscribe, topic}, pid, ref} ->
        topics = Map.put(topics, topic, :lists.delete(pid, Map.get(topics, topic, [])))

        monitors =
          if Enum.any?(topics, fn {_topic, subscribers} -> :lists.member(pid, subscribers) end) do
            monitors
          else
            case Map.get(monitors, pid) do
              nil ->
                monitors

              monitor_ref ->
                :erlang.demonitor(monitor_ref)
                Map.delete(monitors, pid)
            end
          end

        send(pid, {ref, :ok})
        loop(topics, monitors)

      {:broadcast, sender, topic, message} ->
        deliver(Map.get(topics, topic, []), sender, message)
        loop(topics, monitors)

      {:DOWN, ref, :process, pid, _reason} ->
        if Map.get(monitors, pid) == ref do
          topics = remove_pid(topics, pid)
          loop(topics, Map.delete(monitors, pid))
        else
          loop(topics, monitors)
        end
    end
  end

  defp deliver([], _sender, _message), do: :ok

  defp deliver([pid | rest], sender, message) do
    if pid != sender, do: send(pid, message)
    deliver(rest, sender, message)
  end

  defp remove_pid(topics, pid) do
    :maps.map(fn _topic, subscribers -> :lists.delete(pid, subscribers) end, topics)
  end
end

defmodule Phoenix.LiveView do
  @moduledoc false
  defmacro __using__(_opts), do: :ok
end

defmodule Phoenix.LiveComponent do
  @moduledoc false
  defmacro __using__(_opts), do: :ok
end

defmodule Phoenix.LiveView.Router do
  @moduledoc false
  defmacro live(_path, _module, _action \\ nil), do: :ok
  defmacro live_session(_name, _opts \\ [], _block), do: :ok
end

defmodule Phoenix.LiveView.Socket do
  @moduledoc false
end

defmodule Phoenix.LiveView.JS do
  @moduledoc false
  defstruct ops: []

  def show(%__MODULE__{} = js, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:show, opts}]}

  def show(%__MODULE__{} = js, selector) when is_binary(selector),
    do: show(js, to: selector)

  def show(opts) when is_list(opts), do: show(%__MODULE__{}, opts)
  def show(selector) when is_binary(selector), do: show(%__MODULE__{}, to: selector)

  def hide(%__MODULE__{} = js, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:hide, opts}]}

  def hide(%__MODULE__{} = js, selector) when is_binary(selector),
    do: hide(js, to: selector)

  def hide(opts) when is_list(opts), do: hide(%__MODULE__{}, opts)
  def hide(selector) when is_binary(selector), do: hide(%__MODULE__{}, to: selector)

  def toggle(%__MODULE__{} = js, selector),
    do: %{js | ops: js.ops ++ [{:toggle, selector}]}

  def toggle(selector) when is_binary(selector), do: toggle(%__MODULE__{}, selector)

  def dispatch(%__MODULE__{} = js, event, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:dispatch, event, opts}]}

  def dispatch(event, opts \\ [])

  def dispatch(event, opts) when is_binary(event) and is_list(opts),
    do: dispatch(%__MODULE__{}, event, opts)

  def push(%__MODULE__{} = js, event, opts) when is_binary(event) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:push, event, opts}]}

  def push(event, opts \\ [])

  def push(event, opts) when is_binary(event) and is_list(opts),
    do: push(%__MODULE__{}, event, opts)

  def navigate(href) when is_binary(href), do: navigate(%__MODULE__{}, href, [])

  def navigate(href, opts) when is_binary(href) and is_list(opts),
    do: navigate(%__MODULE__{}, href, opts)

  def navigate(%__MODULE__{} = js, href) when is_binary(href),
    do: navigate(js, href, [])

  def navigate(%__MODULE__{} = js, href, opts) when is_binary(href) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:navigate, href, opts}]}

  def patch(href) when is_binary(href), do: patch(%__MODULE__{}, href, [])

  def patch(href, opts) when is_binary(href) and is_list(opts),
    do: patch(%__MODULE__{}, href, opts)

  def patch(%__MODULE__{} = js, href) when is_binary(href),
    do: patch(js, href, [])

  def patch(%__MODULE__{} = js, href, opts) when is_binary(href) and is_list(opts),
    do: %{js | ops: js.ops ++ [{:patch, href, opts}]}

  def remove_attribute(js_or_attr, attr_or_opts \\ [])

  def remove_attribute(%__MODULE__{} = js, attr) when not is_list(attr),
    do: remove_attribute(js, attr, [])

  def remove_attribute(attr, opts) when not is_struct(attr) and is_list(opts),
    do: remove_attribute(%__MODULE__{}, attr, opts)

  def remove_attribute(%__MODULE__{} = js, attr, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:remove_attribute, attr, opts}]}

  def set_attribute(js_or_tuple, tuple_or_opts \\ [])

  def set_attribute(%__MODULE__{} = js, tuple) when not is_list(tuple),
    do: set_attribute(js, tuple, [])

  def set_attribute(tuple, opts) when not is_struct(tuple) and is_list(opts),
    do: set_attribute(%__MODULE__{}, tuple, opts)

  def set_attribute(%__MODULE__{} = js, tuple, opts) when is_list(opts),
    do: %{js | ops: js.ops ++ [{:set_attribute, tuple, opts}]}
end

defimpl Phoenix.HTML.Safe, for: Phoenix.LiveView.JS do
  def to_iodata(%Phoenix.LiveView.JS{ops: ops}) do
    encoded =
      ops
      |> :erlang.term_to_binary()
      |> Base.encode64()

    ["[[COMPAT,", encoded, "]]"]
  end
end

defimpl String.Chars, for: Phoenix.LiveView.JS do
  def to_string(js), do: Phoenix.HTML.Safe.to_iodata(js) |> IO.iodata_to_binary()
end

defmodule Phoenix.LiveView.LiveStream do
  @moduledoc false
  defstruct [:name, :dom_id]
end

defmodule Phoenix.LiveReloader do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

defmodule Phoenix.LiveReloader.Socket do
  @moduledoc false
end

defmodule Phoenix.LiveDashboard.Router do
  @moduledoc false
  defmacro live_dashboard(_path, _opts \\ []), do: :ok
end

defmodule Phoenix.LiveDashboard.RequestLogger do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

defmodule Phoenix.Ecto.CheckRepoStatus do
  @moduledoc false
  def call(conn, _opts), do: conn
  def init(opts), do: opts
end

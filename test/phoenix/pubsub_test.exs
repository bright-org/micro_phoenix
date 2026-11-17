defmodule Phoenix.PubSubTest do
  use ExUnit.Case

  test "delivers a broadcast to subscribers except the sender" do
    {:ok, server} = Phoenix.PubSub.start_link(name: :micro_phoenix_pubsub_test)
    Process.unlink(server)
    on_exit(fn -> Process.exit(server, :kill) end)

    parent = self()

    subscriber =
      spawn(fn ->
        :ok = Phoenix.PubSub.subscribe(:micro_phoenix_pubsub_test, "room:lobby")
        send(parent, :subscribed)

        receive do
          message -> send(parent, {:delivered, message})
        end
      end)

    assert_receive :subscribed
    :ok = Phoenix.PubSub.subscribe(:micro_phoenix_pubsub_test, "room:lobby")
    :ok = Phoenix.PubSub.broadcast_from(:micro_phoenix_pubsub_test, self(), "room:lobby", :hello)
    assert_receive {:delivered, :hello}
    refute_receive :hello, 50
    Process.exit(subscriber, :kill)
  end

  test "removes a subscriber when its process exits" do
    {:ok, server} = Phoenix.PubSub.start_link(name: :micro_phoenix_pubsub_cleanup_test)
    Process.unlink(server)
    on_exit(fn -> Process.exit(server, :kill) end)
    parent = self()

    subscriber =
      spawn(fn ->
        :ok = Phoenix.PubSub.subscribe(:micro_phoenix_pubsub_cleanup_test, "room:lobby")
        send(parent, :subscribed)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :subscribed
    assert {:monitors, [{:process, ^subscriber}]} = Process.info(server, :monitors)
    Process.exit(subscriber, :kill)

    assert Enum.any?(1..20, fn _ ->
             if Process.info(server, :monitors) == {:monitors, []} do
               true
             else
               Process.sleep(10)
               false
             end
           end)
  end

  test "unsubscribes one topic without losing subscriptions to others" do
    {:ok, server} = Phoenix.PubSub.start_link(name: :micro_phoenix_pubsub_multi_test)
    Process.unlink(server)
    on_exit(fn -> Process.exit(server, :kill) end)

    :ok = Phoenix.PubSub.subscribe(server, "room:first")
    :ok = Phoenix.PubSub.subscribe(server, "room:second")
    assert {:monitors, [_]} = Process.info(server, :monitors)

    :ok = Phoenix.PubSub.unsubscribe(server, "room:first")
    assert {:monitors, [_]} = Process.info(server, :monitors)
    :ok = Phoenix.PubSub.broadcast(server, "room:first", :stale)
    :ok = Phoenix.PubSub.broadcast(server, "room:second", :current)
    assert_receive :current
    refute_receive :stale, 50

    :ok = Phoenix.PubSub.unsubscribe(server, "room:second")
    assert Process.info(server, :monitors) == {:monitors, []}
  end
end

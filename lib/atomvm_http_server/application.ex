defmodule AtomvmHttpServer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AtomvmHttpServer.Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AtomvmHttpServer.Supervisor)
  end
end


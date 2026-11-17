defmodule MicroPhoenix.EndpointLiveProbe do
  def start do
    Phoenix.AtomVM.run(MicroPhoenix.EndpointRouteProbe.Router,
      port: 18080,
      static: []
    )
  end
end

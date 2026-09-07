ExUnit.start()

Application.put_env(:micro_phoenix, :static_root, Path.expand("test/fixtures/static", __DIR__))

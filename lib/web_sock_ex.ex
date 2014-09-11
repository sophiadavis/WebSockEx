defmodule WebSockEx do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec
    {:ok, port} = Application.fetch_env(:web_sock_ex, :port)

    children = [
      supervisor(Task.Supervisor, [[name: :server_pool]], id: :server_pool),
      supervisor(Task.Supervisor, [[name: :connection]], id: :connection), # TODO shared state??
      worker(Task, [WebSockEx.Server, :accept, [port]])
    ]

    opts = [strategy: :one_for_one]
    Supervisor.start_link(children, opts)
  end
end

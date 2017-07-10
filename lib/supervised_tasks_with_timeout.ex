defmodule Sup do
  require Logger
  alias Sup.Spec
  alias Sup.Handle

  defmodule Handle do
    @type t :: %__MODULE__{}
    defstruct master_ref: nil
  end

  defmodule Spec do
    @type t :: %__MODULE__{}
    defstruct mfas: [], hard_timeout_ms: 0, soft_timeout_ms: 0
  end

  def start(%Spec{mfas: mfas, hard_timeout_ms: hard_timeout_ms, soft_timeout_ms: soft_timeout_ms}) do
    master_pid = self() # request process
    master_ref = make_ref()

    Task.async(fn ->
      process(master_pid, master_ref, mfas, hard_timeout_ms, soft_timeout_ms)
    end)

    %Handle{master_ref: master_ref}
  end

  def wait(%Handle{master_ref: master_ref}, hard_timeout_ms \\ 5000) do
    IO.puts("waiting for result >>")
    receive do
      {:ok, ^master_ref} ->
        IO.puts("got result >>")
        :ok
    after hard_timeout_ms ->
      :ok
    end
  end

  defp process(master_pid, master_ref, mfas, hard_timeout_ms, soft_timeout_ms) do
    {:ok, sup_pid} = Task.Supervisor.start_link()
    kill_timeout_ref = make_ref()
    soft_timeout_ref = make_ref()
    Process.send_after(self(), {:kill_timeout, kill_timeout_ref}, hard_timeout_ms)
    Process.send_after(self(), {:soft_timeout, soft_timeout_ref}, soft_timeout_ms)

    IO.inspect [">>", sup_pid]

    Process.flag(:trap_exit, true)
    tasks = Enum.map(mfas, fn {m, f, a} ->
      Task.Supervisor.async(sup_pid, m, f, a)
    end)

    wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
    send(master_pid, {:ok, master_ref})

    IO.puts("DONE>>>>")
  end

  def wait_for_tasks(sup_pid, [], _, _, _, _), do: Supervisor.stop(sup_pid)
  def wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, master_pid, master_ref) do
    receive do
      {:kill_timeout, ^kill_timeout_ref} ->
        Supervisor.stop(sup_pid)
      {:soft_timeout, ^soft_timeout_ref} ->
        send(master_pid, {:ok, master_ref})
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
      {ref, _result} ->
        wait_for_tasks(sup_pid, remove_tasks(tasks, ref), kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
      {:EXIT, _, _} ->
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
      {:DOWN, ref, _, _, _} ->
        wait_for_tasks(sup_pid, remove_tasks(tasks, ref), kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
      oops ->
        Logger.warn("unexpected message: #{inspect oops}")
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, master_pid, master_ref)
    end
  end

  def remove_tasks(tasks, ref) do
    Enum.reject(tasks, fn t -> t.ref == ref end)
  end

end

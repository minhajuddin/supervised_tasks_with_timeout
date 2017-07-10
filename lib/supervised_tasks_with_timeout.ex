defmodule Sup do
  require Logger

  alias Sup.Spec
  alias Sup.Handle
  alias Sup.State

  defmodule Handle do
    @type t :: %__MODULE__{}
    defstruct wait_ref: nil
  end

  defmodule Spec do
    @type t :: %__MODULE__{}
    defstruct mfas: [], hard_timeout_ms: 0, soft_timeout_ms: 0
  end

  defmodule State do
    @type t :: %__MODULE__{}
    defstruct sup_pid: nil,
      calling_pid: nil,
      kill_timeout_ref: nil,
      soft_timeout_ref: nil,
      kill_timer: nil,
      soft_timer: nil,
      wait_ref: nil
  end

  def start(%Spec{mfas: mfas, hard_timeout_ms: hard_timeout_ms, soft_timeout_ms: soft_timeout_ms}) do
    calling_pid = self() # request process
    wait_ref = make_ref()

    Task.async(fn ->
      process(calling_pid, wait_ref, mfas, hard_timeout_ms, soft_timeout_ms)
    end)

    %Handle{wait_ref: wait_ref}
  end

  def wait(%Handle{wait_ref: wait_ref}, timeout_ms \\ 90_000) do
    receive do
      {:ok, ^wait_ref} ->
        :ok
    after timeout_ms ->
      :ok
    end
  end

  defp process(calling_pid, wait_ref, mfas, hard_timeout_ms, soft_timeout_ms) do
    {:ok, sup_pid} = Task.Supervisor.start_link()
    kill_timeout_ref = make_ref()
    soft_timeout_ref = make_ref()
    kill_timer = Process.send_after(self(), {:kill_timeout, kill_timeout_ref}, hard_timeout_ms)
    soft_timer = Process.send_after(self(), {:soft_timeout, soft_timeout_ref}, soft_timeout_ms)

    Process.flag(:trap_exit, true)
    tasks = Enum.map(mfas, fn {m, f, a} ->
      Task.Supervisor.async(sup_pid, m, f, a)
    end)

    state = %State{sup_pid: sup_pid, kill_timeout_ref: kill_timeout_ref,
      soft_timeout_ref: soft_timeout_ref,
      calling_pid: calling_pid, wait_ref: wait_ref,
      kill_timer: kill_timer, soft_timer: soft_timer}
    wait_for_tasks(state, tasks)

    notify_caller(state)
  end

  defp notify_caller(%State{calling_pid: calling_pid, wait_ref: wait_ref,
    soft_timer: soft_timer}) do
    send(calling_pid, {:ok, wait_ref})
    Process.cancel_timer(soft_timer)
  end

  defp wait_for_tasks(%State{sup_pid: sup_pid, kill_timer: kill_timer}, []) do
    Supervisor.stop(sup_pid)
    Process.cancel_timer(kill_timer)
  end

  defp wait_for_tasks(%State{kill_timeout_ref: kill_timeout_ref,
    soft_timeout_ref: soft_timeout_ref} = state, tasks) do
    receive do
      {:kill_timeout, ^kill_timeout_ref} ->
        Supervisor.stop(state.sup_pid)
      {:soft_timeout, ^soft_timeout_ref} ->
        notify_caller(state)
        wait_for_tasks(state, tasks)
      {ref, _result} ->
        wait_for_tasks(state, remove_tasks(tasks, ref))
      {:EXIT, _, _} ->
        wait_for_tasks(state, tasks)
      {:DOWN, ref, _, _, _} ->
        wait_for_tasks(state, remove_tasks(tasks, ref))
      oops ->
        Logger.warn("unexpected message: #{inspect oops}")
        wait_for_tasks(state, tasks)
    end
  end

  defp remove_tasks(tasks, ref) do
    Enum.reject(tasks, fn t -> t.ref == ref end)
  end

end

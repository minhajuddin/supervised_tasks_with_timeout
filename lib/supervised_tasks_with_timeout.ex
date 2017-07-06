defmodule Sup do
  require Logger

  def start do
    calling_pid = self() # request process
    ref = make_ref()

    Task.async(fn ->
      process(calling_pid, ref)
    end)

    IO.puts("waiting for result >>")
    receive do
      {:ok, ^ref} ->
        IO.puts("got result >>")
        :ok
    after :timer.seconds(4) ->
      :ok
    end
  end

  def process(from, from_ref) do
    {:ok, sup_pid} = Task.Supervisor.start_link()
    kill_timeout_ref = make_ref()
    soft_timeout_ref = make_ref()
    Process.send_after(self(), {:kill_timeout, kill_timeout_ref}, :timer.seconds(5))
    Process.send_after(self(), {:soft_timeout, soft_timeout_ref}, :timer.seconds(3))

    IO.inspect [">>", sup_pid]

    Process.flag(:trap_exit, true)
    tasks = Enum.map(1..10,
              fn idx ->

                Task.Supervisor.async(sup_pid, fn ->
                  IO.puts("started worker #{idx} #{inspect self()}")
                  :timer.sleep(idx * 100)
                  if idx == 2 do
                    raise "Baaa"
                  end
                  if idx == 4 do
                    IO.puts "waiting longer ...."
                    :timer.sleep(idx * 6000)
                    IO.puts "finished waiting longer ...."
                  end
                  IO.puts("finished worker #{idx}")
                  :ok
                end)

              end)

    tasks |> Enum.each(fn t -> IO.puts "REF: #{inspect t.ref}" end)

    wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, from, from_ref)
    send(from, {:ok, from_ref})

    IO.puts("DONE>>>>")
  end

  def wait_for_tasks(sup_pid, [], _, _, _, _), do: Supervisor.stop(sup_pid)
  def wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, from, from_ref) do
    receive do
      {:kill_timeout, ^kill_timeout_ref} ->
        Supervisor.stop(sup_pid)
      {:soft_timeout, ^soft_timeout_ref} ->
        send(from, {:ok, from_ref})
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, from, from_ref)
      {ref, _result} ->
        wait_for_tasks(sup_pid, remove_tasks(tasks, ref), kill_timeout_ref, soft_timeout_ref, from, from_ref)
      {:EXIT, _, _} ->
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, from, from_ref)
      {:DOWN, ref, _, _, _} ->
        wait_for_tasks(sup_pid, remove_tasks(tasks, ref), kill_timeout_ref, soft_timeout_ref, from, from_ref)
      oops ->
        Logger.warn("unexpected message: #{inspect oops}")
        wait_for_tasks(sup_pid, tasks, kill_timeout_ref, soft_timeout_ref, from, from_ref)
    end
  end

  def remove_tasks(tasks, ref) do
    Enum.reject(tasks, fn t -> t.ref == ref end)
  end

end

defmodule SupTest do
  use ExUnit.Case

  defmodule Worker do
    def work(units, caller_pid, message) do
      IO.puts "working"
      :timer.sleep(units)
      send(caller_pid, message)
      IO.puts "finished working"
    end
  end

  test "start executes mfa" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [5, self(), :done]}], hard_timeout_ms: 100,
      soft_timeout_ms: 10})

    Sup.wait(sup_handle)

    assert_received :done
  end

  test "start executes multiple mfas" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [50, self(), :bar]}, {Worker, :work, [50, self(), :foo]}], hard_timeout_ms: 100,
      soft_timeout_ms: 60})

    refute_received :foo
    refute_received :bar

    Sup.wait(sup_handle)

    assert_received :foo
    assert_received :bar
  end

  test "wait returns on soft_timeout" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [20, self(), :done]}], hard_timeout_ms: 120,
      soft_timeout_ms: 10})

    refute_received :done
    Sup.wait(sup_handle)
    refute_received :done

    :timer.sleep(10)
    assert_received :done
  end

  test "wait kills mfas on hard_timeout" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [10, self(), :pass]},
                                            {Worker, :work, [40, self(), :fail]}],
      hard_timeout_ms: 30, soft_timeout_ms: 20})

    refute_received :pass
    refute_received :fail
    Sup.wait(sup_handle)
    assert_received :pass
    refute_received :fail

    :timer.sleep(40)
    refute_received :fail
  end

  test "wait kills mfas on hard_timeout 2" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [10, self(), :pass]},
                                            {Worker, :work, [40, self(), :fail]}],
      hard_timeout_ms: 30, soft_timeout_ms: 30})

    refute_received :pass
    refute_received :fail
    Sup.wait(sup_handle)
    assert_received :pass
    refute_received :fail

    :timer.sleep(30)
    refute_received :fail
  end

  defmodule ErrorWorker do
    def work do
      raise "An error occured"
    end
  end

  test "failure in worker should not stop other workers" do
    sup_handle = Sup.start(%Sup.Spec{mfas: [{Worker, :work, [10, self(), :pass]},
                                            {ErrorWorker, :work, []}],
      hard_timeout_ms: 30, soft_timeout_ms: 30})

    Sup.wait(sup_handle)
    assert_received :pass
  end
end

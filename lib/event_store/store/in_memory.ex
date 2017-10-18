defmodule EventStore.Store.InMemory do
  use Agent
  @behaviour EventStore.Store.Adapter

  defstruct [events: %{}, snapshots: %{}]

  def start_link do
    Agent.start_link(
      &new_store/0,
      name: __MODULE__
    )
  end

  def commit_events!([]), do: []
  def commit_events!(events) do
    Agent.get_and_update(__MODULE__, &update_events(&1, events))
  end

  def commit_snapshot(snapshot) do
    Agent.get_and_update(__MODULE__, &update_snapshot(&1, snapshot))
  end

  def get_events(id, seq \\ 0) do
    Agent.get(__MODULE__, &return_events(&1, id, seq))
  end

  def get_snapshot(id, seq \\ 0) do
    Agent.get(__MODULE__, &return_snapshot(&1, id, seq))
  end

  def reset, do: Agent.update(__MODULE__, &new_store/1)

  defp update_events(%{events: all_events} = state, new_events) do
    aid = new_events |> List.first() |> aggregate_id()
    old_events  = Map.get(all_events, aid, [])

    if overlapping?(old_events, new_events) do
      {{:error, :retry_command}, state}
    else
      {new_events, %{state | events: Map.put(
                        all_events,
                        aid,
                        old_events ++ new_events
                      )}}
    end
  end

  defp update_snapshot(%{snapshots: snaps} = state, new_snap) do
    aid = aggregate_id(new_snap)
    prev_snap = Map.get(snaps, aid, %{sequence: -1})
    if prev_snap.sequence > new_snap.sequence do
      {:ok, state}
    else
      {:ok, %{state | snapshots: Map.put(snaps, aid, new_snap)}}
    end
  end

  defp return_events(%{events: events}, id, seq) do
    events
    |> Map.get(id, [])
    |> Enum.filter(fn (e) -> e.sequence > seq end)
  end

  defp return_snapshot(%{snapshots: snaps}, id, seq) do
    snap = snaps |> Map.get(id, %{sequence: -1})
    if snap.sequence > seq do
      snap
    else
      nil
    end
  end

  defp new_store, do: %__MODULE__{}
  defp new_store(_), do: new_store()

  defp overlapping?(old_events, new_events) do
    pseqs = Enum.map(old_events, &sequence/1)
    cseqs = Enum.map(new_events, &sequence/1)

    Enum.count(pseqs -- cseqs) != Enum.count(pseqs)
  end

  defp sequence(%{sequence: sequence}), do: sequence

  defp aggregate_id(%{aggregate_id: a}), do: a
end
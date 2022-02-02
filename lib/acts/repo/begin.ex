if Code.ensure_loaded?(Bonfire.Common.Utils) do
  defmodule Bonfire.Epics.Acts.Repo.Begin do
    @moduledoc """
    An Act that enters a transaction if there are no changeset errors
    """
    require Logger
    import Bonfire.Common.Utils
    alias Bonfire.Epics.{Act, Acts.Repo.Commit, Epic}
    require Act

    def run(epic, act) do
      # take all the modules before commit and run them, then return the remainder.
      {next, rest} = Enum.split_while(epic.next, &(&1.module != Commit))
      rest = Enum.drop(rest, 1) # drop commit if there are any items left
      nested = %{ epic | next: next }
      # if there are already errors, we will assume nothing is going to write and skip the transaction.
      if epic.errors == [] do
        Act.debug(act, "entering transaction")
        Bonfire.Repo.transact_with(fn ->
          epic = Epic.run(nested)
          if epic.errors == [], do: {:ok, epic}, else: {:error, epic}
        end)
        |> case do
          {:ok, epic} ->
            Act.debug(act, "committed successfully.")
            %{ epic | next: rest }
          {:error, epic} ->
            Act.debug(act, "rollback because of errors")
            %{ epic | next: rest }
        end
      else
        Act.debug(act, "not entering transaction because of errors")
        Epic.run(nested)
        %{ epic | next: rest }
      end
    end
  end
end

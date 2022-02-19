if Code.ensure_loaded?(Bonfire.Common.Utils) do
  defmodule Bonfire.Epics.Acts.Repo.Insert do
    @moduledoc """
    An Act that enters a transaction if there are no changeset errors
    """
    import Bonfire.Common.Utils
    alias Bonfire.Epics.{Act, Epic}
    alias Bonfire.Repo
    alias Ecto.Changeset
    require Act
    import Where

    def run(epic, act) do
      if epic.errors == [] do
        # work through the inputs to discover which are actually present
        changesets =
          Keyword.fetch!(act.options, :changesets)
          |> Enum.flat_map(&get_changeset(epic, act, &1))
        invalid = Enum.reject(changesets, fn {c,_,_} -> c.valid? end)
        if invalid == [] do
          Act.debug(act, "No changeset errors, proceeding to insert.")
          do_inserts(epic, act, changesets)
        else
          Act.debug(act, "Not proceeding because of changeset errors at keys: #{inspect(Enum.map(invalid, &elem(&1, 1)))}.")
          Enum.reduce(invalid, epic, fn {cs,_,_}, epic ->
            Epic.add_error(epic, act, cs, :changeset)
          end)
        end
      else
        Act.debug(act, length(epic.errors), "Skipping because of epic errors")
        epic
      end
    end


    # collates all the changesets that are present along with their source and destination keys.
    defp get_changeset(epic, act, source_and_dest_key) when is_atom(source_and_dest_key),
      do: get_changeset(epic, act, source_and_dest_key, source_and_dest_key)

    defp get_changeset(epic, act, {dest_key, source_key}) when is_atom(source_key) and is_atom(dest_key),
      do: get_changeset(epic, act, source_key, dest_key)

    defp get_changeset(epic, act, source_key, dest_key) do
      case epic.assigns[source_key] do
        nil ->
          Act.debug(act, "Assigns key #{source_key} is nil, not inserting to #{dest_key}")
          []
        %Changeset{valid?: true}=cs ->
          [{cs, source_key, dest_key}]
      end
    end

    defp do_inserts(epic, act, changesets) do
      case changesets do
        [] -> epic
        [{cs, source_key, dest_key}|rest] ->
          case Repo.insert(cs) do
            {:ok, cs} ->
              Act.debug(act, "Inserted #{source_key} as #{dest_key}")
              do_inserts(Epic.assign(epic, dest_key, cs), act, rest)
            {:error, cs} ->
              Act.debug(act, "Aborting because of changeset errors at key: #{source_key}.")
              Epic.add_error(epic, act, cs, :changeset)
          end
      end
    end
  end
end

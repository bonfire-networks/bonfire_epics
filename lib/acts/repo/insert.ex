if Code.ensure_loaded?(Bonfire.Common.Utils) do
  defmodule Bonfire.Epics.Acts.Repo.Insert do
    @moduledoc """
    An Act that enters a transaction if there are no changeset errors
    """
    import Bonfire.Common.Utils
    alias Bonfire.Epics
    alias Bonfire.Epics.{Act, Epic}
    alias Bonfire.Repo
    alias Ecto.Changeset
    import Epics
    import Where

    def run(%Epic{} = epic, %Act{} = act) do
      if epic.errors == [] do
        # work through the inputs to discover which are actually present
        changesets =
          Keyword.fetch!(act.options, :changesets)
          |> Enum.flat_map(&get_changeset(epic, act, &1))
        invalid = Enum.reject(changesets, fn {c,_,_} -> c.valid? end)
        if invalid == [] do
          maybe_debug(act, "No changeset errors, proceeding to insert.", "insert")
          do_inserts(epic, act, changesets)
        else
          maybe_debug(act, Enum.map(invalid, &elem(&1, 1)), "Not proceeding because of changeset errors at keys")
          Enum.reduce(invalid, epic, fn {cs,_,_}, epic ->
            Epic.add_error(epic, act, cs, :changeset)
          end)
        end
      else
        maybe_debug(act, length(epic.errors), "Skipping because of epic errors")
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
          maybe_debug(act, "Assigns key #{source_key} is nil, not inserting to #{dest_key}", "insert")
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
              maybe_debug(act, "Inserted #{source_key} as #{dest_key}", "insert")
              do_inserts(Epic.assign(epic, dest_key, cs), act, rest)
            {:error, cs} ->
              maybe_debug(act, source_key, "Aborting because of changeset errors at key")
              Epic.add_error(epic, act, cs, :changeset)
          end
      end
    end
  end
end

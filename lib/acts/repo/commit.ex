if Code.ensure_loaded?(Bonfire.Common.Utils) do
  defmodule Bonfire.Epics.Acts.Repo.Commit do
    @moduledoc """
    A placeholder marker used by Begin to identify when to commit the transaction.
    """

    def run(epic, act) do
      raise RuntimeError, message: """
      Commit without Begin!

      epic: #{inspect(epic)}

      act: #{inspect(act)}
      """
    end
  end
end

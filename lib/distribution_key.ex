# SPDX-FileCopyrightText: 2024 ash_sql contributors <https://github.com/ash-project/ash_sql/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshSql.DistributionKey do
  @moduledoc false

  # Adds the distribution key equality (see `c:AshSql.Implementation.distribution_key/1`)
  # to the join conditions that relate two resources.
  #
  # A side of the join is addressed as:
  #
  #   * `{:as, binding}` - a named binding of the query being built
  #   * `{:parent_as, binding}` - a named binding of the parent query (lateral joins
  #     and correlated subqueries)
  #   * `:first` - the first positional binding (the `from`)
  #   * `:last` - the last positional binding (the join being added)

  import Ecto.Query, only: [dynamic: 1, dynamic: 2]

  @type ref :: {:as, term} | {:parent_as, term} | :first | :last

  @doc "The distribution key of a resource, if the sql behaviour declares one."
  @spec key(module, Ash.Resource.t()) :: atom | nil
  def key(sql_behaviour, resource) do
    # `many_to_many` relationships may name a list of relationships as `through`
    if is_atom(resource) and Ash.Resource.Info.resource?(resource) and
         function_exported?(sql_behaviour, :distribution_key, 1) do
      sql_behaviour.distribution_key(resource)
    end
  end

  @doc """
  Joins `condition` with `source.key == destination.key` when both resources declare a key.

  `condition` may be `nil`, in which case the equality alone (or `nil`) is returned.
  """
  @spec join_on(
          Ecto.Query.dynamic_expr() | nil,
          module,
          {Ash.Resource.t(), ref},
          {Ash.Resource.t(), ref}
        ) :: Ecto.Query.dynamic_expr() | nil
  def join_on(condition, sql_behaviour, {source_resource, source_ref}, {dest_resource, dest_ref}) do
    with source_key when not is_nil(source_key) <- key(sql_behaviour, source_resource),
         dest_key when not is_nil(dest_key) <- key(sql_behaviour, dest_resource) do
      equality = dynamic(^field_ref(source_ref, source_key) == ^field_ref(dest_ref, dest_key))

      if is_nil(condition) do
        equality
      else
        dynamic(^condition and ^equality)
      end
    else
      _ -> condition
    end
  end

  defp field_ref({:as, binding}, key), do: dynamic(field(as(^binding), ^key))
  defp field_ref({:parent_as, binding}, key), do: dynamic(field(parent_as(^binding), ^key))
  defp field_ref(:first, key), do: dynamic([row], field(row, ^key))
  defp field_ref(:last, key), do: dynamic([..., row], field(row, ^key))
end

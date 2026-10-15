# SPDX-FileCopyrightText: 2024 ash_sql contributors <https://github.com/ash-project/ash_sql/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshSql.DistributionKeyTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 1, dynamic: 2]

  alias AshSql.DistributionKey

  defmodule Distributed do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key(:id)
      attribute(:tenant_id, :string)
    end
  end

  defmodule Plain do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key(:id)
    end
  end

  defmodule Behaviour do
    use AshSql.Implementation

    def table(_), do: "table"
    def schema(_), do: nil
    def repo(_, _), do: nil
    def parameterized_type(type, _), do: type
    def determine_types(_, args), do: {args, nil}
    def manual_relationship_function, do: :join
    def manual_relationship_subquery_function, do: :subquery

    def distribution_key(Distributed), do: :tenant_id
    def distribution_key(_), do: nil
  end

  defmodule NoKeys do
    use AshSql.Implementation

    def table(_), do: "table"
    def schema(_), do: nil
    def repo(_, _), do: nil
    def parameterized_type(type, _), do: type
    def determine_types(_, args), do: {args, nil}
    def manual_relationship_function, do: :join
    def manual_relationship_subquery_function, do: :subquery
  end

  describe "key/2" do
    test "returns the behaviour's distribution key for the resource" do
      assert DistributionKey.key(Behaviour, Distributed) == :tenant_id
      assert DistributionKey.key(Behaviour, Plain) == nil
    end

    test "defaults to nil for behaviours that do not declare one" do
      assert DistributionKey.key(NoKeys, Distributed) == nil
    end

    test "is nil for anything that is not a resource" do
      assert DistributionKey.key(Behaviour, [:a, :b]) == nil
      assert DistributionKey.key(Behaviour, NotAResource) == nil
    end
  end

  describe "join_on/4" do
    test "adds the key equality when both resources declare one" do
      condition = dynamic([..., d], field(as(^0), :id) == field(d, :parent_id))

      joined =
        DistributionKey.join_on(
          condition,
          Behaviour,
          {Distributed, {:as, 0}},
          {Distributed, :last}
        )

      assert inspect(joined) ==
               "dynamic([..., d], as(0).id == ....parent_id and as(0).tenant_id == ....tenant_id)"
    end

    test "supports parent_as and first bindings" do
      joined =
        DistributionKey.join_on(
          nil,
          Behaviour,
          {Distributed, {:parent_as, 3}},
          {Distributed, :first}
        )

      assert inspect(joined) =~ "parent_as(3).tenant_id == "
      assert inspect(joined) =~ ".tenant_id)"
    end

    test "leaves the condition alone when either side has no key" do
      condition = dynamic([..., d], field(as(^0), :id) == field(d, :parent_id))

      assert DistributionKey.join_on(
               condition,
               Behaviour,
               {Distributed, {:as, 0}},
               {Plain, :last}
             ) ==
               condition

      assert DistributionKey.join_on(
               condition,
               Behaviour,
               {Plain, {:as, 0}},
               {Distributed, :last}
             ) ==
               condition

      assert DistributionKey.join_on(nil, Behaviour, {Plain, {:as, 0}}, {Distributed, :last}) ==
               nil
    end
  end
end

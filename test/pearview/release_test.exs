defmodule Pearview.ReleaseTest do
  use Pearview.DataCase, async: true

  import Pearview.ShoppingFixtures

  alias Pearview.Release
  alias Pearview.Shopping

  describe "seed_data/0" do
    test "seeds more than one store, so multi-store works out of the box" do
      assert Release.seed_data() == :ok

      assert length(Shopping.list_stores()) > 1
    end

    test "gives every seeded store its own route, in walking order, with hints" do
      Release.seed_data()

      for store <- Shopping.list_stores() do
        sections = Shopping.list_sections(store)

        assert length(sections) > 1
        assert Enum.map(sections, & &1.position) == Enum.to_list(1..length(sections))
        assert Enum.all?(sections, &(&1.hints not in [nil, ""]))
      end
    end

    test "selects the first seeded store, so the Shopper view opens on a route" do
      Release.seed_data()

      assert Shopping.get_selected_store().name == "Tesco Extra"
    end

    test "is idempotent: re-seeding adds no duplicate stores or sections" do
      Release.seed_data()
      stores = Shopping.list_stores()
      sections = Enum.flat_map(stores, &Shopping.list_sections/1)

      Release.seed_data()

      assert Enum.map(Shopping.list_stores(), & &1.id) == Enum.map(stores, & &1.id)

      assert length(Enum.flat_map(Shopping.list_stores(), &Shopping.list_sections/1)) ==
               length(sections)
    end

    test "never overwrites a selection the Shopper has already made" do
      Release.seed_data()
      lidl = Enum.find(Shopping.list_stores(), &(&1.name == "Lidl"))
      select!(lidl)

      Release.seed_data()

      assert Shopping.get_selected_store().id == lidl.id
    end
  end
end

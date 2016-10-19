defmodule LensTest do
  use ExUnit.Case
  require Integer
  doctest Lens

  describe "key" do
    test "to_list", do: assert Lens.to_list(%{a: :b}, Lens.key(:a)) == [:b]

    test "each" do
      this = self
      Lens.each(%{a: :b}, Lens.key(:a), fn x -> send(this, x) end)
      assert_receive :b
    end

    test "map", do: assert Lens.map(%{a: :b}, Lens.key(:a), fn :b -> :c end) == %{a: :c}

    test "get_and_map" do
      assert Lens.get_and_map(%{a: :b}, Lens.key(:a), fn :b -> {:c, :d} end) == {[:c], %{a: :d}}
    end
  end

  describe "keys" do
    test "get_and_map" do
      assert Lens.get_and_map(%{a: :b, c: :d, e: :f}, Lens.keys([:a, :e]), fn x-> {x, :x} end) ==
        {[:b, :f], %{a: :x, c: :d, e: :x}}
    end
  end

  describe "all" do
    test "to_list", do: assert Lens.to_list([:a, :b, :c], Lens.all) == [:a, :b, :c]

    test "each" do
      this = self
      Lens.each([:a, :b, :c], Lens.all, fn x -> send(this, x) end)
      assert_receive :a
      assert_receive :b
      assert_receive :c
    end

    test "map", do: assert Lens.map([:a, :b, :c], Lens.all, fn :a -> 1; :b -> 2; :c -> 3 end) == [1, 2, 3]

    test "get_and_map" do
      assert Lens.get_and_map([:a, :b, :c], Lens.all, fn x -> {x, :d} end) == {[:a, :b, :c], [:d, :d, :d]}
    end
  end

  describe "filter" do
    test "get_and_map" do
      assert Lens.get_and_map([1, 2, 3, 4], Lens.filter(&Integer.is_odd/1), fn n -> {n, n + 1} end) ==
        {[1, 3], [2, 2, 4, 4]}
    end
  end

  describe "seq" do
    test "to_list", do: assert Lens.to_list(%{a: %{b: :c}}, Lens.seq(Lens.key(:a), Lens.key(:b))) == [:c]

    test "each" do
      this = self
      Lens.each(%{a: %{b: :c}}, Lens.seq(Lens.key(:a), Lens.key(:b)), fn x -> send(this, x) end)
      assert_receive :c
    end

    test "map", do: assert Lens.map(%{a: %{b: :c}}, Lens.seq(Lens.key(:a), Lens.key(:b)), fn :c -> :d end) == %{a: %{b: :d}}

    test "get_and_map" do
      assert Lens.get_and_map(%{a: %{b: :c}}, Lens.seq(Lens.key(:a), Lens.key(:b)), fn :c -> {:d, :e} end) == {[:d], %{a: %{b: :e}}}
    end
  end

  describe "seq_both" do
    test "get_and_map" do
      assert Lens.get_and_map(%{a: %{b: :c}}, Lens.seq_both(Lens.key(:a), Lens.key(:b)), fn
        :c -> {2, :d}
        %{b: :d} -> {1, %{b: :e}}
      end) == {[2, 1], %{a: %{b: :e}}}
    end
  end

  describe "both" do
    test "get_and_map" do
      assert Lens.get_and_map(%{a: 1, b: [2, 3]}, Lens.both(Lens.key(:a), Lens.seq(Lens.key(:b), Lens.all)), fn x -> {x, x + 1} end) ==
        {[1, 2, 3], %{a: 2, b: [3, 4]}}
    end
  end

  describe "satisfy" do
    test "get_and_map" do
      lens =
        Lens.both(Lens.keys([:a, :b]), Lens.seq(Lens.key(:c), Lens.all))
        |> Lens.satisfy(fn n -> Integer.is_odd(n) end)
      assert Lens.get_and_map(%{a: 1, b: 2, c: [3, 4]}, lens, fn x -> {x, x + 1} end) ==
        {[1, 3], %{a: 2, b: 2, c: [4, 4]}}
    end
  end

  describe "recur" do
    test "get_and_map" do
      data = %{
        data: 1,
        items: [
          %{data: 2, items: []},
          %{data: 3, items: [
            %{data: 4, items: []}
          ]}
        ]
      }

      lens = Lens.recur(Lens.seq(Lens.key(:items), Lens.all)) |> Lens.seq(Lens.key(:data))

      assert Lens.get_and_map(data, lens, fn x -> {x, x + 1} end) == {[2, 3, 4], %{
        data: 1,
        items: [
          %{data: 3, items: []},
          %{data: 4, items: [
            %{data: 5, items: []}
          ]}
        ]}}
    end
  end
end

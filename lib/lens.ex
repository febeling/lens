defmodule Lens do
  use Lens.Macros

  @opaque t :: (:get, any, function -> list(any)) | (:get_and_update, any, function -> {list(any), any})

  @doc ~S"""
  Returns a lens that does not focus on any part of the data.

      iex> Lens.empty |> Lens.to_list(:anything)
      []
      iex> Lens.empty |> Lens.map(1, &(&1 + 1))
      1
  """
  @spec empty :: t
  deflens_raw empty do
    fn data, _fun -> {[], data} end
  end

  @doc ~S"""
  Returns a lens that ignores the data and always focuses on the given value.

      iex> Lens.const(3) |> Lens.one!(:anything)
      3
      iex> Lens.const(3) |> Lens.map(1, &(&1 + 1))
      4
      iex> import Integer
      iex> lens = Lens.keys([:a, :b]) |> Lens.match(fn v -> if is_odd(v), do: Lens.root, else: Lens.const(0) end)
      iex> Lens.map(lens, %{a: 11, b: 12}, &(&1 + 1))
      %{a: 12, b: 1}
  """
  @spec const(any) :: t
  deflens_raw const(value) do
    fn _data, fun ->
      {res, updated} = fun.(value)
      {[res], updated}
    end
  end

  @doc ~S"""
  Returns a lens that yields the entirety of the data currently under focus.

      iex> Lens.to_list(Lens.root, :data)
      [:data]
      iex> Lens.map(Lens.root, :data, fn :data -> :other_data end)
      :other_data
      iex> Lens.key(:a) |> Lens.both(Lens.root, Lens.key(:b)) |> Lens.to_list(%{a: %{b: 1}})
      [%{b: 1}, 1]
  """
  @spec root :: t
  deflens_raw root do
    fn data, fun ->
      {res, updated} = fun.(data)
      {[res], updated}
    end
  end

  @doc ~S"""
  Select the lens to use based on a matcher function

      iex> selector = fn
      ...>   {:a, _} -> Lens.at(1)
      ...>   {:b, _, _} -> Lens.at(2)
      ...> end
      iex> Lens.match(selector) |> Lens.one!({:b, 2, 3})
      3
  """
  @spec match((any -> t)) :: t
  deflens_raw match(matcher_fun) do
    fn data, fun ->
      get_and_map(matcher_fun.(data), data, fun)
    end
  end

  @doc ~S"""
  Returns a lens that focuses on the n-th element of a list or tuple.

      iex> Lens.at(2) |> Lens.one!({:a, :b, :c})
      :c
      iex> Lens.at(1) |> Lens.map([:a, :b, :c], fn :b -> :d end)
      [:a, :d, :c]
  """
  @spec at(non_neg_integer) :: t
  deflens_raw at(index) do
    fn data, fun ->
      {res, updated} = fun.(get_at_index(data, index))
      {[res], set_at_index(data, index, updated)}
    end
  end

  @doc ~S"""
  An alias for `at`.
  """
  @spec index(non_neg_integer) :: t
  deflens index(index) do
    at(index)
  end

  @doc ~S"""
  Returns a lens that focuses on all of the supplied indices.

      iex> Lens.indices([0, 2]) |> Lens.to_list([:a, :b, :c])
      [:a, :c]
      iex> Lens.indices([0, 2]) |> Lens.map([1, 2, 3], &(&1 + 1))
      [2, 2, 4]
  """
  @spec indices([non_neg_integer]) :: t
  deflens indices(indices) do
    indices |> Enum.map(&index/1) |> multiple
  end

  @doc ~S"""
  Returns a lens that focuses between a given index and the previous one in a list. It will always return a nil when
  accessing, but can be used to insert elements.

      iex> Lens.before(2) |> Lens.one!([:a, :b, :c])
      nil
      iex> Lens.before(2) |> Lens.map([:a, :b, :c], fn nil -> :d end)
      [:a, :b, :d, :c]
  """
  @spec before(non_neg_integer) :: t
  deflens_raw before(index) do
    fn data, fun ->
      {res, item} = fun.(nil)
      {init, tail} = Enum.split(data, index)
      {[res], init ++ [item] ++ tail}
    end
  end

  @doc ~S"""
  Returns a lens that focuses between a given index and the next one in a list. It will always return a nil when
  accessing, but can be used to insert elements.

      iex> Lens.behind(1) |> Lens.one!([:a, :b, :c])
      nil
      iex> Lens.behind(1) |> Lens.map([:a, :b, :c], fn nil -> :d end)
      [:a, :b, :d, :c]
  """
  @spec behind(non_neg_integer) :: t
  deflens_raw behind(index) do
    fn data, fun ->
      {res, item} = fun.(nil)
      {init, tail} = Enum.split(data, index + 1)
      {[res], init ++ [item] ++ tail}
    end
  end

  @doc ~S"""
  Returns a lens that focuses before the first element of a list. It will always return a nil when accessing, but can
  be used to prepend elements.

      iex> Lens.front |> Lens.one!([:a, :b, :c])
      nil
      iex> Lens.front |> Lens.map([:a, :b, :c], fn nil -> :d end)
      [:d, :a, :b, :c]
  """
  @spec front :: t
  deflens front do
    before(0)
  end

  @doc ~S"""
  Returns a lens that focuses after the last element of a list. It will always return a nil when accessing, but can
  be used to append elements.

      iex> Lens.back |> Lens.one!([:a, :b, :c])
      nil
      iex> Lens.back |> Lens.map([:a, :b, :c], fn nil -> :d end)
      [:a, :b, :c, :d]
  """
  @spec back :: t
  deflens_raw back do
    fn data, fun ->
      data |> Enum.count() |> behind |> get_and_map(data, fun)
    end
  end

  @doc ~S"""
  Returns a lens that focuses on the value under `key`.

      iex> Lens.to_list(Lens.key(:foo), %{foo: 1, bar: 2})
      [1]
      iex> Lens.map(Lens.key(:foo), %{foo: 1, bar: 2}, fn x -> x + 10 end)
      %{foo: 11, bar: 2}

  If the key doesn't exist in the map a nil will be returned or passed to the update function.

      iex> Lens.to_list(Lens.key(:foo), %{})
      [nil]
      iex> Lens.map(Lens.key(:foo), %{}, fn nil -> 3 end)
      %{foo: 3}
  """
  @spec key(any) :: t
  deflens_raw key(key) do
    fn data, fun ->
      {res, updated} = fun.(get_at_key(data, key))
      {[res], set_at_key(data, key, updated)}
    end
  end

  @doc ~S"""
  Returns a lens that focuses on the value under the given key. If the key does not exist an error will be raised.

      iex> Lens.key!(:a) |> Lens.one!(%{a: 1, b: 2})
      1
      iex> Lens.key!(:a) |> Lens.one!([a: 1, b: 2])
      1
      iex> Lens.key!(:c) |> Lens.one!(%{a: 1, b: 2})
      ** (KeyError) key :c not found in: %{a: 1, b: 2}
  """
  @spec key!(any) :: t
  deflens_raw key!(key) do
    fn data, fun ->
      {res, updated} = fun.(fetch_at_key!(data, key))
      {[res], set_at_key(data, key, updated)}
    end
  end

  @doc ~S"""
  Returns a lens that focuses on the value under the given key. If they key does not exist it focuses on nothing.

      iex> Lens.key?(:a) |> Lens.to_list(%{a: 1, b: 2})
      [1]
      iex> Lens.key?(:a) |> Lens.to_list([a: 1, b: 2])
      [1]
      iex> Lens.key?(:c) |> Lens.to_list(%{a: 1, b: 2})
      []
  """
  @spec key?(any) :: t
  deflens_raw key?(key) do
    fn data, fun ->
      case fetch_at_key(data, key) do
        :error ->
          {[], data}

        {:ok, value} ->
          {res, updated} = fun.(value)
          {[res], set_at_key(data, key, updated)}
      end
    end
  end

  @doc ~S"""
  Returns a lens that focuses on the values of all the keys.

      iex> Lens.keys([:a, :c]) |> Lens.to_list(%{a: 1, b: 2, c: 3})
      [1, 3]
      iex> Lens.keys([:a, :c]) |> Lens.map([a: 1, b: 2, c: 3], &(&1 + 1))
      [a: 2, b: 2, c: 4]

  If any of the keys doesn't exist the update function will receive a nil.

      iex> Lens.keys([:a, :c]) |> Lens.map(%{a: 1, b: 2}, fn nil -> 3; x -> x end)
      %{a: 1, b: 2, c: 3}
  """
  @spec keys(nonempty_list(any)) :: t
  deflens keys(keys) do
    keys |> Enum.map(&Lens.key/1) |> multiple
  end

  @doc ~S"""
  Returns a lens that focuses on the values of all the keys. If any of the keys does not exist, an error is raised.

      iex> Lens.keys!([:a, :c]) |> Lens.to_list(%{a: 1, b: 2, c: 3})
      [1, 3]
      iex> Lens.keys!([:a, :c]) |> Lens.map([a: 1, b: 2, c: 3], &(&1 + 1))
      [a: 2, b: 2, c: 4]
      iex> Lens.keys!([:a, :c]) |> Lens.to_list(%{a: 1, b: 2})
      ** (KeyError) key :c not found in: %{a: 1, b: 2}
  """
  @spec keys!(nonempty_list(any)) :: t
  deflens keys!(keys) do
    keys |> Enum.map(&Lens.key!/1) |> multiple
  end

  @doc ~S"""
  Returns a lens that focuses on the values of all the keys. If any of the keys does not exist, it is ignored.

      iex> Lens.keys?([:a, :c]) |> Lens.to_list(%{a: 1, b: 2, c: 3})
      [1, 3]
      iex> Lens.keys?([:a, :c]) |> Lens.map([a: 1, b: 2, c: 3], &(&1 + 1))
      [a: 2, b: 2, c: 4]
      iex> Lens.keys?([:a, :c]) |> Lens.to_list(%{a: 1, b: 2})
      [1]
  """
  @spec keys?(nonempty_list(any)) :: t
  deflens keys?(keys) do
    keys |> Enum.map(&Lens.key?/1) |> multiple
  end

  @doc ~S"""
  Returns a lens that focuses on all the values in an enumerable.

      iex> Lens.all |> Lens.to_list([1, 2, 3])
      [1, 2, 3]

  Does work with updates but produces a list from any enumerable by default:

      iex> Lens.all |> Lens.map(MapSet.new([1, 2, 3]), &(&1 + 1))
      [2, 3, 4]

  See [into](#into/2) on how to rectify this.
  """
  @spec all :: t
  deflens_raw all do
    fn data, fun ->
      {res, updated} =
        Enum.reduce(data, {[], []}, fn item, {res, updated} ->
          {res_item, updated_item} = fun.(item)
          {[res_item | res], [updated_item | updated]}
        end)

      {Enum.reverse(res), Enum.reverse(updated)}
    end
  end

  @doc ~S"""
  Compose a pair of lens by applying the second to the result of the first

      iex> Lens.seq(Lens.key(:a), Lens.key(:b)) |> Lens.one!(%{a: %{b: 3}})
      3

  Piping lenses has the exact same effect:

      iex> Lens.key(:a) |> Lens.key(:b) |> Lens.one!(%{a: %{b: 3}})
      3
  """
  @spec seq(t, t) :: t
  deflens_raw seq(lens1, lens2) do
    fn data, fun ->
      {res, changed} =
        get_and_map(lens1, data, fn item ->
          get_and_map(lens2, item, fun)
        end)

      {Enum.concat(res), changed}
    end
  end

  @doc ~S"""
  Combine the composition of both lens with the first one.

      iex> Lens.seq_both(Lens.key(:a), Lens.key(:b)) |> Lens.to_list(%{a: %{b: :c}})
      [:c, %{b: :c}]
  """
  @spec seq_both(t, t) :: t
  deflens seq_both(lens1, lens2) do
    both(seq(lens1, lens2), lens1)
  end

  @doc ~S"""
  Make a lens recursive

      iex> data = %{
      ...>    items: [
      ...>      %{v: 1, items: []},
      ...>      %{v: 2, items: [
      ...>        %{v: 3, items: []}
      ...>      ]}
      ...> ]}
      iex> lens = Lens.recur(Lens.key(:items) |> Lens.all) |> Lens.key(:v)
      iex> Lens.to_list(lens, data)
      [1, 3, 2]
  """
  @spec recur(t) :: t
  deflens_raw recur(lens) do
    &do_recur(lens, &1, &2)
  end

  @doc ~s"""
  Returns a lens that focuses on what both the lenses focus on.

      iex> Lens.both(Lens.key(:a), Lens.key(:b) |> Lens.at(1)) |> Lens.to_list(%{a: 1, b: [2, 3]})
      [1, 3]

  Bear in mind that what the first lens focuses on will be processed first. Other functions in the library are designed
  so that the part is processed before the whole and it is advisable to do the same when using this function directly.
  Not adhering to this principle might lead to the second lens not being able to perform its traversal on a changed
  version of the structure.

      iex> Lens.both(Lens.root, Lens.key(:a)) |> Lens.get_and_map(%{a: 1}, fn x -> {x, :foo} end)
      ** (FunctionClauseError) no function clause matching in Access.fetch/2
      iex> Lens.both(Lens.key(:a), Lens.root) |> Lens.get_and_map(%{a: 1}, fn x -> {x, :foo} end)
      {[1, %{a: :foo}], :foo}
  """
  @spec both(t, t) :: t
  deflens_raw both(lens1, lens2) do
    fn data, fun ->
      {res1, changed1} = get_and_map(lens1, data, fun)
      {res2, changed2} = get_and_map(lens2, changed1, fun)
      {res1 ++ res2, changed2}
    end
  end

  @doc """
  Combines the two provided lenses in a way similar to `seq`. However instead of only focusing on what the final lens
  would focus on it focuses on pairs of the form `{context, part}`, where context is the focus of the first lens in
  which the focus of the second lens was found.

      iex> lens = Lens.context(Lens.keys([:a, :c]), Lens.key(:b) |> Lens.all())
      iex> Lens.to_list(lens, %{a: %{b: [1, 2]}, c: %{b: [3]}})
      [{%{b: [1, 2]}, 1}, {%{b: [1, 2]}, 2}, {%{b: [3]}, 3}]
      iex> Lens.map(lens, %{a: %{b: [1, 2]}, c: %{b: [3]}}, fn({%{b: bs}, value}) ->
      ...>   length(bs) + value
      ...> end)
      %{a: %{b: [3, 4]}, c: %{b: [4]}}
  """
  @spec context(t, t) :: t
  deflens_raw context(context_lens, item_lens) do
    fn data, fun ->
      {results, changed} =
        get_and_map(context_lens, data, fn context ->
          get_and_map(item_lens, context, fn item -> fun.({context, item}) end)
        end)

      {Enum.concat(results), changed}
    end
  end

  @doc ~S"""
  Returns a lens that focuses on what all of the supplied lenses focus on.

      iex> Lens.multiple([Lens.key(:a), Lens.key(:b), Lens.root]) |> Lens.to_list(%{a: 1, b: 2})
      [1, 2, %{a: 1, b: 2}]
  """
  @spec multiple([t]) :: t
  deflens multiple(lenses) do
    lenses |> Enum.reverse() |> Enum.reduce(empty(), &both/2)
  end

  @doc ~S"""
  Returns a lens that does not change the focus of of the given lens, but puts the results into the given collectable
  when updating.

      iex> Lens.all |> Lens.into(MapSet.new) |> Lens.map(MapSet.new([-2, -1, 1, 2]), &(&1 * &1))
      MapSet.new([1, 4])
  """
  deflens_raw into(lens, collectable) do
    fn data, fun ->
      {res, updated} = get_and_map(lens, data, fun)
      {res, Enum.into(updated, collectable)}
    end
  end

  @doc ~S"""
  Returns a lens that focuses on a subset of elements focused on by the given lens that satisfy the given condition.

      iex> Lens.map_values() |> Lens.filter(&Integer.is_odd/1) |> Lens.to_list(%{a: 1, b: 2, c: 3, d: 4})
      [1, 3]
  """
  @spec filter(t, (any -> boolean)) :: t
  deflens_raw filter(lens, filter_fun) do
    fn data, fun ->
      {res, changed} =
        get_and_map(lens, data, fn item ->
          if filter_fun.(item) do
            {res, changed} = fun.(item)
            {[res], changed}
          else
            {[], item}
          end
        end)

      {Enum.concat(res), changed}
    end
  end

  @doc false
  @deprecated "Use filter/2 instead"
  @spec satisfy(t, (any -> boolean)) :: t
  def satisfy(lens, filter_fun), do: filter(lens, filter_fun)

  @doc ~S"""
  Returns a lens that focuses on a subset of elements focused on by the given lens that don't satisfy the given
  condition.

      iex> Lens.map_values() |> Lens.reject(&Integer.is_odd/1) |> Lens.to_list(%{a: 1, b: 2, c: 3, d: 4})
      [2, 4]
  """
  @spec reject(t, (any -> boolean)) :: t
  def reject(lens, filter_fun), do: filter(lens, &(not filter_fun.(&1)))

  @doc ~S"""
  Returns a lens that focuses on all values of a map.

      iex> Lens.map_values() |> Lens.to_list(%{a: 1, b: 2})
      [1, 2]
      iex> Lens.map_values() |> Lens.map(%{a: 1, b: 2}, &(&1 + 1))
      %{a: 2, b: 3}
  """
  @spec map_values :: t
  deflens map_values do
    all() |> into(%{}) |> at(1)
  end

  @doc ~S"""
  Returns a lens that focuses on all keys of a map.

      iex> Lens.map_keys() |> Lens.to_list(%{a: 1, b: 2})
      [:a, :b]
      iex> Lens.map_keys() |> Lens.map(%{1 => :a, 2 => :b}, &(&1 + 1))
      %{2 => :a, 3 => :b}
  """
  @spec map_keys :: t
  deflens map_keys do
    all() |> into(%{}) |> at(0)
  end

  @doc ~S"""
  Returns a list of values that the lens focuses on in the given data.

      iex> Lens.keys([:a, :c]) |> Lens.to_list(%{a: 1, b: 2, c: 3})
      [1, 3]
  """
  @spec to_list(t, any) :: list(any)
  def to_list(lens, data), do: get_in(data, [lens])

  @doc ~S"""
  Performs a side effect for each values this lens focuses on in the given data.

      iex> data = %{a: 1, b: 2, c: 3}
      iex> fun = fn -> Lens.keys([:a, :c]) |> Lens.each(data, &IO.inspect/1) end
      iex> import ExUnit.CaptureIO
      iex> capture_io(fun)
      "1\n3\n"
  """
  @spec each(t, any, (any -> any)) :: :ok
  def each(lens, data, fun), do: to_list(lens, data) |> Enum.each(fun)

  @doc ~S"""
  Returns an updated version of the data by applying the given function to each value the lens focuses on and building
  a data structure of the same shape with the updated values in place of the original ones.

      iex> data = [1, 2, 3, 4]
      iex> Lens.all() |> Lens.filter(&Integer.is_odd/1) |> Lens.map(data, fn v -> v + 10 end)
      [11, 2, 13, 4]
  """
  @spec map(t, any, (any -> any)) :: any
  def map(lens, data, fun), do: update_in(data, [lens], fun)

  @doc ~S"""
  Returns an updated version of the data and a transformed value from each location the lens focuses on. The
  transformation function must return a tuple `{value_to_return, value_to_update}`.

      iex> data = %{a: 1, b: 2, c: 3}
      iex> Lens.keys([:a, :b, :c])
      ...> |> Lens.filter(&Integer.is_odd/1)
      ...> |> Lens.get_and_map(data, fn v -> {v + 1, v + 10} end)
      {[2, 4], %{a: 11, b: 2, c: 13}}
  """
  @spec get_and_map(t, any, (any -> {any, any})) :: {list(any), any}
  def get_and_map(lens, data, fun), do: get_and_update_in(data, [lens], fun)

  @doc ~S"""
  Executes `to_list` and returns the single item that the given lens focuses on for the given data. Crashes if there
  is more than one item.
  """
  @spec one!(t, any) :: any
  def one!(lens, data) do
    [result] = to_list(lens, data)
    result
  end

  defp do_recur(lens, data, fun) do
    {res, changed} =
      get_and_map(lens, data, fn item ->
        {results, changed1} = do_recur(lens, item, fun)
        {res_parent, changed2} = fun.(changed1)
        {results ++ [res_parent], changed2}
      end)

    {Enum.concat(res), changed}
  end

  defp get_at_key(data, key) do
    case fetch_at_key(data, key) do
      :error -> nil
      {:ok, value} -> value
    end
  end

  defp set_at_key(data, key, value) when is_map(data), do: Map.put(data, key, value)

  defp set_at_key(data, key, value) do
    {_, updated} = Access.get_and_update(data, key, fn _ -> {nil, value} end)
    updated
  end

  defp fetch_at_key!(data, key) do
    case fetch_at_key(data, key) do
      :error -> raise(KeyError, key: key, term: data)
      {:ok, value} -> value
    end
  end

  defp fetch_at_key(data, key) when is_map(data), do: Map.fetch(data, key)
  defp fetch_at_key(data, key), do: Access.fetch(data, key)

  defp get_at_index(data, index) when is_tuple(data), do: elem(data, index)
  defp get_at_index(data, index), do: Enum.at(data, index)

  defp set_at_index(data, index, value) when is_tuple(data), do: put_elem(data, index, value)

  defp set_at_index(data, index, value) when is_list(data) do
    List.update_at(data, index, fn _ -> value end)
  end
end

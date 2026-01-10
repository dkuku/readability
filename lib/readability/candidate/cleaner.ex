defmodule Readability.Candidate.Cleaner do
  @moduledoc """
  Clean HTML tree for prepare candidates.

  It transforms misused tags and removes unlikely candidates.
  """

  alias Readability.Helper

  @type html_tree :: tuple | list

  @doc """
  Transforms misused divs <div>s that do not contain other block elements into <p>s.
  """
  @spec transform_misused_div_to_p(html_tree) :: html_tree
  def transform_misused_div_to_p(content) when is_binary(content), do: content
  def transform_misused_div_to_p([]), do: []

  def transform_misused_div_to_p([h | t]) do
    [transform_misused_div_to_p(h) | transform_misused_div_to_p(t)]
  end

  def transform_misused_div_to_p({tag, attrs, inner_tree}) do
    tag = if misused_divs?(tag, inner_tree), do: "p", else: tag
    {tag, attrs, transform_misused_div_to_p(inner_tree)}
  end

  @doc """
  Removes unlikely HTML tree.
  """
  @spec remove_unlikely_tree(html_tree) :: html_tree
  def remove_unlikely_tree(html_tree) do
    Helper.remove_tag(html_tree, &unlikely_tree?(&1))
  end

  defp misused_divs?("div", inner_tree) do
    !(inner_tree |> LazyHTML.from_tree() |> LazyHTML.to_html() =~
        Readability.Regex.regex(:div_to_p_elements))
  end

  defp misused_divs?(_, _), do: false

  defp unlikely_tree?({tag, attrs, _}) do
    idclass_str =
      attrs
      |> Enum.filter(&(elem(&1, 0) =~ ~r/id|class/i))
      |> Enum.map_join("", &elem(&1, 1))

    str = tag <> idclass_str

    str =~ Readability.Regex.regex(:unlikely_candidate) &&
      !(str =~ Readability.Regex.regex(:ok_maybe_its_a_candidate)) && tag != "html"
  end
end

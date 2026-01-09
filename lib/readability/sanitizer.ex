defmodule Readability.Sanitizer do
  @moduledoc """
  Clean an element of all tags of type "tag" if they look fishy.

  "Fishy" is an algorithm based on content length, classnames, link density,
  number of images & embeds, etc.
  """

  alias Readability.Candidate
  alias Readability.Candidate.Scoring
  alias Readability.Helper
  alias Readability.Queries

  @type html_tree :: tuple | list

  @doc """
  Sanitizes article HTML tree.
  """
  @conditional_clean_tags ~w(table ul div)

  @spec sanitize(html_tree, [Candidate.t()], list) :: html_tree
  def sanitize(html_tree, candidates, opts \\ []) do
    cleaned =
      html_tree
      |> Helper.remove_tag(&clean_headline_tag?/1)
      |> Helper.remove_tag(&clean_unlikely_tag?/1)
      |> Helper.remove_tag(&clean_empty_p?/1)

    if opts[:clean_conditionally],
      do: Helper.remove_tag(cleaned, conditionally_cleaning_fn(candidates)),
      else: cleaned
  end

  defp conditionally_cleaning_fn(candidates) do
    fn {tag, _, _} = tree ->
      tag in @conditional_clean_tags and should_clean?(tree, candidates)
    end
  end

  defp should_clean?({tag, attrs, _} = tree, candidates) do
    weight = Scoring.class_weight(attrs)
    candidate = Enum.find(candidates, %Candidate{}, &(&1.html_tree == tree))

    cond do
      weight + candidate.score < 0 -> true
      Queries.count_character(tree, ",") < 10 -> has_ominous_signs?(tree, tag, weight)
      true -> false
    end
  end

  defp has_ominous_signs?(tree, tag, weight) do
    p_len = tree |> Queries.find_tag("p") |> length()
    img_len = tree |> Queries.find_tag("img") |> length()
    li_len = tree |> Queries.find_tag("li") |> length()
    input_len = tree |> Queries.find_tag("input") |> length()

    embed_len =
      tree
      |> Queries.find_tag("embed")
      |> Enum.reject(&(&1 =~ Readability.regexes(:video)))
      |> length()

    link_density = Scoring.calc_link_density(tree)
    content_len = Queries.text_length(tree)
    list? = tag == "ul"

    img_len > p_len ||
      (!list? && li_len > p_len) ||
      input_len > p_len / 3 ||
      (!list? && content_len < 25 && img_len != 1) ||
      (weight < 25 && link_density > 0.2) ||
      (weight >= 25 && link_density > 0.5) ||
      (embed_len == 1 && content_len < 75) ||
      embed_len > 1
  end

  defp clean_headline_tag?({tag, attrs, _} = html_tree) do
    tag =~ ~r/^h\d{1}$/ &&
      (Scoring.class_weight(attrs) < 0 || Scoring.calc_link_density(html_tree) > 0.33)
  end

  defp clean_unlikely_tag?({tag, attrs, _}) do
    attrs_str = Enum.map_join(attrs, "", &elem(&1, 1))
    tag =~ ~r/form|object|iframe|embed/ && !(attrs_str =~ Readability.regexes(:video))
  end

  defp clean_empty_p?({tag, _, _} = html_tree) do
    tag == "p" && Queries.text_length(html_tree) == 0
  end
end

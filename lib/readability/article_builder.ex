defmodule Readability.ArticleBuilder do
  @moduledoc """
  Build article for readability.
  """

  alias Readability.Candidate
  alias Readability.Candidate.Cleaner
  alias Readability.Candidate.Scoring
  alias Readability.CandidateFinder
  alias Readability.Helper
  alias Readability.Queries
  alias Readability.Sanitizer

  @type html_tree :: tuple | list
  @type options :: list

  @doc """
  Prepare the article node for display.

  Clean out any inline styles, iframes, forms, strip extraneous <p> tags, etc.
  """
  @spec build(html_tree, options) :: html_tree
  @removable_tags ~w(script style)

  def build(%LazyHTML{} = lazy, opts) do
    build(lazy, opts, 0)
  end

  def build(html_tree, opts) do
    build(html_tree, opts, 0)
  end

  def build(%LazyHTML{} = lazy, opts, depth) when depth < 5 do
    lazy
    |> LazyHTML.to_tree()
    |> build(opts, depth + 1)
  end

  def build(%LazyHTML{} = lazy, _opts, _depth) do
    # Fallback to prevent infinite recursion
    LazyHTML.to_tree(lazy)
  end

  def build(html_tree, opts, depth) when is_list(html_tree) do
    origin_tree = html_tree

    prepared =
      html_tree
      |> Helper.remove_tag(fn {tag, _, _} -> tag in @removable_tags end)
      |> maybe_remove_unlikely(opts[:remove_unlikely_candidates])
      |> Cleaner.transform_misused_div_to_p()

    candidates =
      prepared
      |> Queries.cache_stats_in_attributes()
      |> CandidateFinder.find(opts)

    result =
      candidates
      |> find_article(prepared)
      |> Sanitizer.sanitize(candidates, opts)

    if Queries.text_length(result) < opts[:retry_length] and depth < 3 do
      case next_try_opts(opts) do
        nil -> Queries.clear_stats_from_attributes(result)
        new_opts -> build(origin_tree, new_opts, depth + 1)
      end
    else
      Queries.clear_stats_from_attributes(result)
    end
  end

  defp maybe_remove_unlikely(html_tree, true), do: Cleaner.remove_unlikely_tree(html_tree)
  defp maybe_remove_unlikely(html_tree, _), do: html_tree

  defp next_try_opts(opts) do
    cond do
      opts[:remove_unlikely_candidates] ->
        Keyword.put(opts, :remove_unlikely_candidates, false)

      opts[:weight_classes] ->
        Keyword.put(opts, :weight_classes, false)

      opts[:clean_conditionally] ->
        Keyword.put(opts, :clean_conditionally, false)

      true ->
        nil
    end
  end

  defp find_article(candidates, html_tree) do
    candidate = CandidateFinder.find_best_candidate(candidates) || fallback_candidate(html_tree)
    article_trees = find_article_trees(candidate, candidates)
    {"div", [], article_trees}
  end

  defp fallback_candidate(html_tree) do
    case Queries.find_tag(html_tree, "body") do
      [tree | _] -> %Candidate{html_tree: tree}
      _ -> %Candidate{html_tree: {}}
    end
  end

  defp find_article_trees(best_candidate, candidates) do
    score_threshold = Enum.max([10, best_candidate.score * 0.2])

    candidates
    |> Enum.filter(&(&1.tree_depth == best_candidate.tree_depth))
    |> Enum.filter(fn candidate ->
      candidate == best_candidate || candidate.score >= score_threshold || append?(candidate)
    end)
    |> Enum.map(&to_article_tag(&1.html_tree))
  end

  defp append?(%Candidate{html_tree: html_tree}) when elem(html_tree, 0) == "p" do
    link_density = Scoring.calc_link_density(html_tree)
    inner_length = Queries.text_length(html_tree)

    (inner_length > 80 && link_density < 0.25) ||
      (inner_length < 80 && link_density == 0 && tree_text(html_tree) =~ ~r/\.( |$)/)
  end

  defp append?(_), do: false

  defp tree_text({_tag, _attrs, children}) do
    Enum.map_join(children, "", &tree_text/1)
  end

  defp tree_text(text) when is_binary(text), do: text
  defp tree_text(_), do: ""

  defp to_article_tag({tag, attrs, inner_tree} = html_tree) do
    if tag =~ ~r/^p$|^div$/ do
      html_tree
    else
      {"div", attrs, inner_tree}
    end
  end
end

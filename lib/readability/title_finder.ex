defmodule Readability.TitleFinder do
  @moduledoc """
  The TitleFinder engine traverses HTML tree searching for finding title.
  """

  @title_suffix ~r/\s(?:\-|\:\:|\|)\s/
  @h_tag_selector "h1"

  @type html_tree :: tuple | list

  @doc """
  Find proper title.
  """
  @spec title(html_tree) :: binary
  def title(html_tree) do
    case og_title(html_tree) do
      "" ->
        title = tag_title(html_tree)
        h_title = h_tag_title(html_tree)

        if good_title?(title) || h_title == "" do
          title
        else
          h_title
        end

      title when is_binary(title) ->
        title
    end
  end

  @doc """
  Find title from title tag.
  """
  @spec tag_title(html_tree) :: binary
  def tag_title(html_tree) do
    # Try "head title" first, fall back to just "title" for fragments
    lazy = find_tag(html_tree, "head title")
    lazy = if has_matches?(lazy), do: lazy, else: find_tag(html_tree, "title")

    lazy
    |> first_text()
    |> String.split(@title_suffix)
    |> hd()
  end

  @doc """
  Find title from `og:title` property of meta tag.
  """
  @spec og_title(html_tree) :: binary
  def og_title(html_tree) do
    html_tree
    |> LazyHTML.from_tree()
    |> LazyHTML.query("meta[property='og:title']")
    |> LazyHTML.attribute("content")
    |> List.first()
    |> case do
      nil -> ""
      content -> String.trim(content)
    end
  end

  @doc """
  Find title from `h` tag.
  """
  @spec h_tag_title(html_tree, String.t()) :: binary
  def h_tag_title(html_tree, selector \\ @h_tag_selector) do
    html_tree
    |> find_tag(selector)
    |> first_text()
  end

  defp find_tag(html_tree, selector) do
    html_tree
    |> LazyHTML.from_tree()
    |> LazyHTML.query(selector)
  end

  defp has_matches?(%LazyHTML{} = lazy_html) do
    lazy_html |> LazyHTML.to_tree() |> Enum.any?()
  end

  defp first_text(%LazyHTML{} = lazy_html) do
    case LazyHTML.to_tree(lazy_html) do
      [] -> ""
      [first | _] -> [first] |> LazyHTML.from_tree() |> LazyHTML.text() |> String.trim()
    end
  end

  defp good_title?(title) do
    length(String.split(title, " ")) >= 4
  end
end

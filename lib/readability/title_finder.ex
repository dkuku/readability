defmodule Readability.TitleFinder do
  @moduledoc """
  The TitleFinder engine traverses HTML tree searching for finding title.
  """

  @title_suffix ~r/\s(?:\-|::|\|)\s/
  @h_tag_selector "h1"

  @type html_tree :: tuple | list
  @type lazy :: LazyHTML.t()

  @doc """
  Find proper title using Mozilla Readability.js priority order.
  """
  @spec title(lazy) :: binary
  def title(lazy) do
    case og_title(lazy) do
      "" ->
        title = tag_title(lazy)
        h_title = h_tag_title(lazy)

        if good_title?(title) or h_title == "" do
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
  @spec tag_title(lazy) :: binary
  def tag_title(lazy) do
    title_text =
      lazy
      |> LazyHTML.query("head title:first-of-type")
      |> LazyHTML.text()
      |> String.trim()

    if title_text == "" do
      lazy
      |> LazyHTML.query("title:first-of-type")
      |> LazyHTML.text()
      |> String.trim()
      |> clean_title_suffix()
    else
      clean_title_suffix(title_text)
    end
  end

  @doc """
  Find title from `og:title` property of meta tag.
  """
  @spec og_title(lazy) :: binary
  def og_title(lazy) do
    lazy
    |> LazyHTML.query("meta[property='og:title']:first-of-type")
    |> LazyHTML.attribute("content")
    |> case do
      [] -> ""
      [content] -> String.trim(content)
    end
  end

  @doc """
  Find title from `h` tag.
  """
  @spec h_tag_title(lazy, String.t()) :: binary
  def h_tag_title(lazy, selector \\ @h_tag_selector) do
    lazy
    |> LazyHTML.query(selector <> ":first-of-type")
    |> LazyHTML.text()
    |> String.trim()
  end

  # Remove common title suffixes following Mozilla Readability.js pattern
  defp clean_title_suffix(title) do
    case String.split(title, @title_suffix, parts: 2) do
      [main_title, _] -> main_title
      [single_part] -> single_part
    end
  end

  defp good_title?(title) do
    title
    |> String.split(" ")
    |> length()
    |> Kernel.>=(4)
  end
end

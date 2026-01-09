defmodule Readability.AuthorFinder do
  @moduledoc """
  AuthorFinder extracts authors.
  """

  @type html_tree :: tuple | list

  @doc """
  Extract authors.
  """
  @spec find(html_tree) :: [binary]
  def find(html_tree) do
    html_tree
    |> find_by_meta_tag()
    |> case do
      nil -> nil
      names -> split_author_names(names)
    end
  end

  defp find_by_meta_tag(html_tree) do
    html_tree
    |> LazyHTML.from_tree()
    |> LazyHTML.query("meta[name*=author], meta[property*=author]")
    |> LazyHTML.attribute("content")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
  end

  defp split_author_names(author_name) do
    author_name
    |> String.split(~r/,\s|\sand\s|by\s/i)
    |> Enum.reject(&(&1 == ""))
  end
end

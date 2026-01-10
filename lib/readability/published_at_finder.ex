defmodule Readability.PublishedAtFinder do
  @moduledoc """
  Extract the published at.
  """

  @type html_tree :: tuple | list

  @doc """
  Extract the published at.
  """
  @spec find(html_tree) :: %DateTime{} | %Date{} | nil
  @selectors [
    {"meta[property='article:published_time'], meta[property='article:published']", "content"},
    {"time", "datetime"},
    {"[data-datetime]", "data-datetime"}
  ]

  def find(lazy) do
    @selectors
    |> Enum.find_value(fn {selector, attr} -> query_first_attr(lazy, selector, attr) end)
    |> case do
      nil -> nil
      value -> parse(value)
    end
  end

  defp query_first_attr(lazy, selector, attr) do
    lazy
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(attr)
    |> Enum.map(&String.trim/1)
    |> List.first()
  end

  defp parse(value) do
    parse(:datetime, value) || parse(:date, value)
  end

  defp parse(:datetime, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse(:date, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end

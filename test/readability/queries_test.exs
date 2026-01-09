defmodule Readability.QueriesTest do
  use ExUnit.Case, async: true

  alias Readability.Queries

  @sample """
    <html>
      <body>
        <p>
          <font>a</font>
          <p>
            <font>abc</font>
            <img src="https://example.org/images/foo.png">
          </p>
        </p>
        <p>
          <span>This is some text, lalala!</span>
          <!-- some comment to test -->
          <img class="img" src="/images/bar.png" alt="alt" />
        </p>
      </body>
    </html>
  """

  @html_tree @sample |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  test "inner text length" do
    text = @html_tree |> LazyHTML.from_tree() |> LazyHTML.text()
    assert Queries.text_length(@html_tree) == String.length(text)
  end

  test "inner count characters" do
    text = @html_tree |> LazyHTML.from_tree() |> LazyHTML.text()
    assert Queries.count_character(@html_tree, ",") == (text |> String.split(",") |> length()) - 1
    assert Queries.count_character(@html_tree, "a") == (text |> String.split("a") |> length()) - 1
  end

  test "inner cached count characters" do
    html_tree = Queries.cache_stats_in_attributes(@html_tree)
    text = @html_tree |> LazyHTML.from_tree() |> LazyHTML.text()

    assert Queries.count_character(html_tree, ",") == (text |> String.split(",") |> length()) - 1
    assert Queries.count_character(html_tree, "a") == (text |> String.split("a") |> length()) - 1

    Queries.clear_stats_from_attributes(html_tree)
  end
end

defmodule Readability.Candidate.CleanerTest do
  use ExUnit.Case, async: true

  alias Readability.Candidate.Cleaner

  doctest Cleaner

  @sample """
  <html>
    <head>
      <title>title!</title>
    </head>
    <body class='comment'>
      <div>
        <p class='comment'>a comment</p>
        <div class='comment' id='body'>real content</div>
        <div id="contains_blockquote"><blockquote>something in a table</blockquote></div>
      </div>
    </body>
  </html>
  """

  @html_tree @sample |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  ### Transform misued div

  test "transform divs containing no block elements" do
    html_tree = Cleaner.transform_misused_div_to_p(@html_tree)
    [{tag, _, _} | _] = html_tree |> LazyHTML.from_tree() |> LazyHTML.query("#body") |> LazyHTML.to_tree()

    assert tag == "p"
  end

  test "not transform divs that contain block elements" do
    html_tree = Cleaner.transform_misused_div_to_p(@html_tree)
    [{tag, _, _} | _] = html_tree |> LazyHTML.from_tree() |> LazyHTML.query("#contains_blockquote") |> LazyHTML.to_tree()
    assert tag == "div"
  end

  ### Remove unlikely tag

  test "remove things that have class comment" do
    html_tree = Cleaner.remove_unlikely_tree(@html_tree)
    refute html_tree |> LazyHTML.from_tree() |> LazyHTML.text() =~ ~r/a comment/
  end

  test "not remove body tags" do
    html_tree = Cleaner.remove_unlikely_tree(@html_tree)
    # Body tag with class='comment' is removed as unlikely, but the content remains
    html = html_tree |> LazyHTML.from_tree() |> LazyHTML.to_html()
    assert html =~ "real content"
  end
end

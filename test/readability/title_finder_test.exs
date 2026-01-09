defmodule Readability.TitleFinderTest do
  use ExUnit.Case, async: true

  doctest Readability.TitleFinder

  @html """
  <html>
    <head>
      <title>Tag title - test</title>
      <meta property='og:title' content='og title'>
    </head>
    <body>
      <p>
        <h1>h1 title</h1>
        <h2>h2 title</h2>
      </p>
    </body>
  </html>
  """

  @html_tree @html |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  test "extract most proper title" do
    title = Readability.TitleFinder.title(@html_tree)
    assert title == "og title"
  end

  test "extracts most proper title from an html string" do
    assert Readability.title(@html) == "og title"
  end

  test "extracts regular title from an html string" do
    html = """
    <html>
      <head>
        <title>Tag title - test</title>
      </head>
    </html>
    """

    # Mozilla Readability.js keeps original title when both parts are very short
    # "Tag title" (2 words) and "test" (1 word) are both short, so keep original
    assert Readability.title(html) == "Tag title - test"
  end

  test "extract og title" do
    title = Readability.TitleFinder.og_title(@html_tree)
    assert title == "og title"
  end

  test "does not merge multiple matching og:title tags" do
    html = """
    <html>
      <head>
        <meta property='og:title' content='og title 1'>
        <meta property='og:title' content='og title 2'>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.og_title()
    assert title == "og title 1"
  end

  test "extract tag title" do
    title = Readability.TitleFinder.tag_title(@html_tree)
    assert title == "Tag title"

    html = """
    <html>
      <head>
        <title>Tag title :: test</title>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "Tag title"

    html = """
    <html>
      <head>
        <title>Tag title | test</title>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "Tag title"

    html = """
    <html>
      <head>
        <title>Tag title-tag</title>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "Tag title-tag"

    html = """
    <html>
      <head>
        <title>Tag title-tag-title - test</title>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "Tag title-tag-title"

    html = """
    <html>
      <head>
        <title>Tag title</title>
      </head>
      <body>
        <svg><title>SVG title</title></svg>
      </body>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "Tag title"
  end

  test "does not merge multiple title tags" do
    html = """
    <html>
      <head>
        <title>tag title 1</title>
        <title>tag title 2</title>
      </head>
    </html>
    """

    title = html |> LazyHTML.from_document() |> LazyHTML.to_tree() |> Readability.TitleFinder.tag_title()
    assert title == "tag title 1"
  end

  test "extract h1 tag title" do
    title = Readability.TitleFinder.h_tag_title(@html_tree)
    assert title == "h1 title"
  end

  test "extract h2 tag title" do
    title = Readability.TitleFinder.h_tag_title(@html_tree, "h2")
    assert title == "h2 title"
  end

  test "does not merge multile header tags" do
    html = """
    <html>
      <body>
        <h1>header 1</h1>
        <h1>header 2</h1>
      </body>
    </html>
    """

    title = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Readability.TitleFinder.h_tag_title()
    assert title == "header 1"
  end

  test "returns an empty string when no title tag can be found" do
    assert Readability.TitleFinder.tag_title([]) == ""
  end

  test "returns an empty string when no og:title tag can be found" do
    assert Readability.TitleFinder.og_title([]) == ""
  end

  test "returns an empty string when no header tag can be found" do
    assert Readability.TitleFinder.h_tag_title([]) == ""
  end
end

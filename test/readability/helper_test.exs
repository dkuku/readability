defmodule Readability.HelperTest do
  use ExUnit.Case, async: true

  alias Readability.Helper

  @sample """
    <html>
      <body>
        <p>
          <font>a</fond>
          <p>
            <font>abc</font>
            <img src="https://example.org/images/foo.png">
          </p>
        </p>
        <p>
          <font>b</font>
          <img class="img" src="/images/bar.png" alt="alt" />
        </p>
      </body>
    </html>
  """

  @html_tree @sample |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  test "change font tag to span" do
    result = Helper.change_tag(@html_tree, "font", "span")
    html = result |> LazyHTML.from_tree() |> LazyHTML.to_html()
    assert html =~ "<span>"
    refute html =~ "<font>"
  end

  test "remove tag" do
    result = Helper.remove_tag(@html_tree, fn {tag, _, _} -> tag == "p" end)
    html = result |> LazyHTML.from_tree() |> LazyHTML.to_html()
    refute html =~ "<p>"
  end

  test "remove all tags" do
    result = Helper.remove_tag(@html_tree, fn {tag, _, _} -> tag == "html" end)
    # After removing html tag, only text nodes remain
    assert is_list(result)
  end

  test "strips out special case tags" do
    html =
      "<html><body><p>Hello <? echo esc_html( wired_get_the_byline_name( $related_video ) ); ?></p></body></html>"
      |> Helper.normalize()
      |> LazyHTML.to_html()

    assert html == "<html><head></head><body><p>Hello </p></body></html>"
  end

  test "replaces fonts by spans" do
    input_html = """
    <div>
      <font color="red" face="Verdana, Geneva, sans-serif" size="+1">Hello</font>
      <font>World</font>
    </div>
    """

    _expected_html = """
    <div>
      <span>Hello</span>
      <span>World</span>
    </div>
    """

    result = input_html |> Helper.normalize() |> LazyHTML.to_html()
    assert result =~ "<span>Hello</span>"
    assert result =~ "<span>World</span>"
    refute result =~ "<font>"
  end

  test "transform img relative paths into absolute" do
    foo_url = "https://example.org/images/foo.png"
    bar_url_http = "http://example.org/images/bar.png"
    bar_url_https = "https://example.org/images/bar.png"

    result_without_scheme =
      @sample
      |> Helper.normalize(url: "example.org/blog/a-blog-post")
      |> LazyHTML.to_html()

    result_with_scheme =
      @sample
      |> Helper.normalize(url: "https://example.org/blog/a-blog-post")
      |> LazyHTML.to_html()

    assert result_without_scheme =~ foo_url
    assert result_without_scheme =~ bar_url_http

    assert result_with_scheme =~ foo_url
    assert result_with_scheme =~ bar_url_https
  end

  test "remove_attrs with list of attribute names" do
    tree = {"div", [{"class", "foo"}, {"id", "bar"}, {"style", "color:red"}], ["content"]}
    result = Helper.remove_attrs(tree, ["class", "style"])
    assert result == {"div", [{"id", "bar"}], ["content"]}
  end

  test "remove_attrs with single attribute name as binary" do
    tree = {"div", [{"class", "foo"}, {"id", "bar"}], ["content"]}
    result = Helper.remove_attrs(tree, "class")
    assert result == {"div", [{"id", "bar"}], ["content"]}
  end

  test "remove_attrs with regex" do
    tree = {"div", [{"data-foo", "1"}, {"data-bar", "2"}, {"id", "test"}], ["content"]}
    result = Helper.remove_attrs(tree, ~r/^data-/)
    assert result == {"div", [{"id", "test"}], ["content"]}
  end

  test "remove_attrs passes through binary content" do
    assert Helper.remove_attrs("text content", "class") == "text content"
  end

  test "remove_attrs handles empty list" do
    assert Helper.remove_attrs([], "class") == []
  end

  test "change_tag passes through binary content" do
    assert Helper.change_tag("text content", "div", "span") == "text content"
  end

  test "change_tag handles empty list" do
    assert Helper.change_tag([], "div", "span") == []
  end

  test "remove_tag passes through binary content" do
    assert Helper.remove_tag("text content", fn _ -> true end) == "text content"
  end

  test "remove_tag handles empty list" do
    assert Helper.remove_tag([], fn _ -> true end) == []
  end

  test "normalize filters out HTML comments" do
    html = "<div><!-- comment -->Hello</div>"
    result = Helper.normalize(html)
    html_str = LazyHTML.to_html(result)
    refute html_str =~ "comment"
    assert html_str =~ "Hello"
  end
end

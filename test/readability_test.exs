defmodule ReadabilityTest do
  use ExUnit.Case, async: false

  test "readability for NY Times" do
    html = TestHelper.read_fixture("nytimes.html")
    opts = [clean_conditionally: false]
    nytimes = Readability.article(html, opts)

    nytimes_html = Readability.readable_html(nytimes)

    assert nytimes_html =~ ~r/<div><div>.*<figure id=\"media-100000004245260\">.*<img src=\"https/s

    assert nytimes_html =~ ~r/major priorities/

    nytimes_text = Readability.readable_text(nytimes)
    assert nytimes_text =~ ~r/^Buddhist monks performing as part of/
    assert nytimes_text =~ ~r/one of her major priorities.$/
  end

  test "readability for BBC" do
    html = TestHelper.read_fixture("bbc.html")
    bbc = Readability.article(html)

    bbc_html = Readability.readable_html(bbc)

    assert bbc_html =~ ~r/<div><div>.*<figure>.*<img alt=\"A Microsoft logo/s
    assert bbc_html =~ ~r/connected computing devices/

    bbc_text = Readability.readable_text(bbc)
    # @TODO: Remove image caption when extract only text
    # assert bbc_text =~ ~r/^Microsoft\'s quarterly profit has missed analysts/
    assert bbc_text =~ ~r/connected computing devices\".$/
  end

  test "readability for medium" do
    html = TestHelper.read_fixture("medium.html")
    medium = Readability.article(html)

    medium_html = Readability.readable_html(medium)

    assert medium_html =~ ~r/^<div><div><p id=\"3476\"><strong><em>Background:/
    assert medium_html =~ ~r/recommend button!<\/em><\/h3><\/div><\/div>$/

    medium_text = Readability.readable_text(medium)

    assert medium_text =~ ~r/^Background: I’ve spent the past 6/
    assert medium_text =~ ~r/a lot to me if you hit the recommend button!$/
  end

  test "readability for buzzfeed" do
    html = TestHelper.read_fixture("buzzfeed.html")
    buzzfeed = Readability.article(html)

    buzzfeed_html = Readability.readable_html(buzzfeed)

    assert buzzfeed_html =~ ~r/The FBI no longer needs Apple/

    assert buzzfeed_html =~ ~r/encrypted devices/

    buzzfeed_text = Readability.readable_text(buzzfeed)

    assert buzzfeed_text =~ ~r/The FBI no longer needs Apple/

    assert buzzfeed_text =~ ~r/issue of court orders and encrypted devices.$/
  end

  test "readability for pubmed" do
    html = TestHelper.read_fixture("pubmed.html")
    pubmed = Readability.article(html)

    pubmed_html = Readability.readable_html(pubmed)

    assert pubmed_html =~
             ~r/^<div><div><h4>BACKGROUND AND OBJECTIVES: <\/h4><p><abstracttext>Although strict blood pressure/

    assert pubmed_html =~
             ~r/different mechanisms yielded potent antihypertensive efficacy with safety and decreased plasma BNP levels.<\/abstracttext><\/p><\/div><\/div>$/

    pubmed_text = Readability.readable_text(pubmed)

    assert pubmed_text =~ ~r/^BACKGROUND AND OBJECTIVES: \nAlthough strict blood pressure/

    assert pubmed_text =~
             ~r/with different mechanisms yielded potent antihypertensive efficacy with safety and decreased plasma BNP levels.$/
  end

  test "correctly processing DOCTYPE" do
    html = TestHelper.read_fixture("medium.html")
    html |> Readability.article() |> Readability.readable_html()
  end

  test "raw_html handles tuple input" do
    tree = {"div", [], ["Hello"]}
    result = Readability.raw_html(tree)
    assert result == "<div>Hello</div>"
  end

  test "raw_html handles list input" do
    tree = [{"div", [], ["Hello"]}, {"span", [], ["World"]}]
    result = Readability.raw_html(tree)
    assert result == "<div>Hello</div><span>World</span>"
  end

  test "parse function works (deprecated)" do
    html = "<div>Test</div>"
    result = Readability.parse(html)
    assert %LazyHTML{} = result
  end

  test "regexes returns nil for unknown key" do
    assert Readability.Regex.regex(:unknown_key) == nil
  end

  test "default_options returns options list" do
    opts = Readability.default_options()
    assert Keyword.keyword?(opts)
    assert Keyword.has_key?(opts, :retry_length)
  end
end

defmodule ReadabilityHttpTest do
  use ExUnit.Case, async: true

  setup do
    Application.put_env(:readability, :req_options, plug: {Req.Test, Readability})
    :ok
  end

  test "blank response is parsed as plain text" do
    url = "https://tools.ietf.org/rfc/rfc2616.txt"
    content = TestHelper.read_fixture("rfc2616.txt")

    Req.Test.stub(Readability, fn conn ->
      conn
      |> Plug.Conn.delete_resp_header("content-type")
      |> Plug.Conn.resp(200, content)
    end)

    %Readability.Summary{article_text: result_text} = Readability.summarize(url)

    assert result_text =~ ~r/3 Protocol Parameters/
  end

  test "text/plain response is parsed as plain text" do
    url = "https://tools.ietf.org/rfc/rfc2616.txt"
    content = TestHelper.read_fixture("rfc2616.txt")

    Req.Test.stub(Readability, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.resp(200, content)
    end)

    %Readability.Summary{article_text: result_text} = Readability.summarize(url)

    assert result_text =~ ~r/3 Protocol Parameters/
  end

  test "*ml responses are parsed as markup" do
    url = "https://news.bbc.co.uk/test.html"
    content = TestHelper.read_fixture("bbc.html")
    mimes = ["text/html", "application/xml", "application/xhtml+xml"]

    Enum.each(mimes, fn mime ->
      Req.Test.stub(Readability, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", mime)
        |> Plug.Conn.resp(200, content)
      end)

      %Readability.Summary{article_html: result_html} = Readability.summarize(url)

      assert result_html =~ ~r/connected computing devices/
    end)
  end

  test "response with charset is parsed correctly" do
    url = "https://news.bbc.co.uk/test.html"
    content = TestHelper.read_fixture("bbc.html")

    Req.Test.stub(Readability, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/html; charset=UTF-8")
      |> Plug.Conn.resp(200, content)
    end)

    %Readability.Summary{article_html: result_html} = Readability.summarize(url)

    assert result_html =~ ~r/connected computing devices/
  end

  test "response with content-type in different case is parsed correctly" do
    # HTTP header keys are case insensitive (RFC2616 - Section 4.2)
    url = "https://news.bbc.co.uk/test.html"
    content = TestHelper.read_fixture("bbc.html")

    Req.Test.stub(Readability, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/html; charset=UTF-8")
      |> Plug.Conn.resp(200, content)
    end)

    %Readability.Summary{article_html: result_html} = Readability.summarize(url)

    assert result_html =~ ~r/connected computing devices/
    assert Readability.mime([{"content-Type", "text/html; charset=UTF-8"}]) == "text/html; charset=UTF-8"
  end

  test "custom req_options can be passed to summarize" do
    url = "https://news.bbc.co.uk/test.html"
    content = TestHelper.read_fixture("bbc.html")

    Req.Test.stub(CustomStub, fn conn ->
      Req.Test.html(conn, content)
    end)

    %Readability.Summary{article_html: result_html} =
      Readability.summarize(url, req_options: [plug: {Req.Test, CustomStub}])

    assert result_html =~ ~r/connected computing devices/
  end
end

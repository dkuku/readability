defmodule Readability do
  @moduledoc """
  Readability library for extracting & curating articles.

  ## Example

  ```elixir
  @type html :: binary

  # Just pass url
  %Readability.Summary{title: title, authors: authors, article_html: article} = Readability.summarize(url)

  # Extract title
  Readability.title(html)

  # Extract published at
  Readability.published_at(html)

  # Extract authors.
  Readability.authors(html)

  # Extract only text from article
  article = html
            |> Readability.article
            |> Readability.readable_text

  # Extract article with transformed html
  article = html
            |> Readability.article
            |> Readability.raw_html
  ```
  """

  alias Readability.ArticleBuilder
  alias Readability.AuthorFinder
  alias Readability.Helper
  alias Readability.MetadataFinder
  alias Readability.PublishedAtFinder
  alias Readability.Summary

  @default_options [
    retry_length: 250,
    min_text_length: 25,
    remove_unlikely_candidates: true,
    weight_classes: true,
    clean_conditionally: true,
    remove_empty_nodes: true,
    min_image_width: 130,
    min_image_height: 80,
    ignore_image_format: [],
    blacklist: nil,
    whitelist: nil,
    page_url: nil
  ]

  @markup_mimes ~r/^(application|text)\/[a-z\-_\.\+]+ml(;\s*charset=.*)?$/i

  @type html_tree :: tuple | list
  @type raw_html :: binary
  @type url :: binary
  @type options :: list
  @type headers :: list[tuple]

  @doc """
  Summarize the primary readable content of a webpage.
  """
  @spec summarize(url, options) :: Summary.t()
  def summarize(url, opts \\ []) do
    opts = Keyword.put(opts, :page_url, url)
    httpoison_options = Application.get_env(:readability, :httpoison_options, [])
    %{status_code: _, body: raw, headers: headers} = HTTPoison.get!(url, [], httpoison_options)

    if is_response_markup(headers) do
      html_tree = Helper.normalize(raw, url: url)
      article_tree = ArticleBuilder.build(html_tree, opts)

      %Summary{
        title: title(html_tree),
        authors: authors(html_tree),
        published_at: published_at(html_tree),
        article_html: readable_html(article_tree),
        article_text: readable_text(article_tree)
      }
    else
      %Summary{title: nil, authors: nil, article_html: nil, article_text: raw}
    end
  end

  @doc """
  Extract MIME Type from headers.

  ## Example

      iex> mime = Readability.mime(headers_list)
      "text/html"

  """
  @spec mime(headers) :: String.t()
  def mime(headers \\ []) do
    headers
    |> Enum.find(
      # default
      {"Content-Type", "text/plain"},
      fn {key, _} -> String.downcase(key) == "content-type" end
    )
    |> elem(1)
  end

  @doc """
  Returns true if Content-Type in provided headers list is a markup type,
  else false.

  ## Example

      iex> Readability.is_response_markup?([{"Content-Type", "text/html"}])
      true

  """
  @spec is_response_markup(headers) :: boolean
  def is_response_markup(headers) do
    mime(headers) =~ @markup_mimes
  end

  @doc """
  Extract title

  ## Example

      iex> title = Readability.title(html_str)
      "Some title in html"

  """
  @spec title(binary | html_tree) :: binary
  def title(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> title()
  end

  def title(html_tree) do
    case MetadataFinder.title(html_tree) do
      nil -> get_article_title(html_tree)
      "" -> get_article_title(html_tree)
      title -> title
    end
  end

  defp get_article_title(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)
    raw_title = get_tag_text(lazy, "title")
    h1_title = get_tag_text(lazy, "h1")

    case raw_title do
      nil -> h1_title || ""
      "" -> h1_title || ""
      title -> MetadataFinder.clean_title(title, html_tree)
    end
  end

  defp get_tag_text(lazy, selector) do
    case lazy |> LazyHTML.query(selector) |> LazyHTML.to_tree() do
      [] -> nil
      [first | _] -> [first] |> LazyHTML.from_tree() |> LazyHTML.text() |> String.trim() |> non_empty_or_nil()
    end
  end

  defp non_empty_or_nil(""), do: nil
  defp non_empty_or_nil(str), do: str

  @doc """
  Extract authors.

  ## Example

      iex> authors = Readability.authors(html_str)
      ["José Valim", "chrismccord"]

  """
  @spec authors(binary | html_tree) :: list[binary]
  def authors(html) when is_binary(html), do: html |> LazyHTML.from_document() |> LazyHTML.to_tree() |> authors()
  def authors(html_tree), do: AuthorFinder.find(html_tree)

  @doc """
  Extract byline (author) following Mozilla Readability.js priority order.

  ## Example

      iex> byline = Readability.byline(html_str)
      "John Doe"

  """
  @spec byline(binary | html_tree) :: binary | nil
  def byline(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> byline()
  end

  def byline(html_tree), do: MetadataFinder.byline(html_tree)

  @doc """
  Extract published_at

  ## Example

      iex> datetime = Readability.published_at(html_str)
      %DateTime{}

  """
  @spec published_at(binary | html_tree) :: %DateTime{} | %Date{} | nil
  def published_at(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> published_at()
  end

  def published_at(html_tree), do: PublishedAtFinder.find(html_tree)

  @doc """
  Extract excerpt/description from meta tags.

  ## Example

      iex> excerpt = Readability.excerpt(html_str)
      "Article description..."

  """
  @spec excerpt(binary | html_tree) :: binary | nil
  def excerpt(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> excerpt()
  end

  def excerpt(html_tree), do: MetadataFinder.excerpt(html_tree)

  @doc """
  Extract site name from meta tags.

  ## Example

      iex> site_name = Readability.site_name(html_str)
      "Example Site"

  """
  @spec site_name(binary | html_tree) :: binary | nil
  def site_name(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> site_name()
  end

  def site_name(html_tree), do: MetadataFinder.site_name(html_tree)

  @doc """
  Extract language from html tag or meta tags.

  ## Example

      iex> lang = Readability.lang(html_str)
      "en"

  """
  @spec lang(binary | html_tree) :: binary | nil
  def lang(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> lang()
  end

  def lang(html_tree), do: MetadataFinder.lang(html_tree)

  @doc """
  Extract text direction from html tag.

  ## Example

      iex> dir = Readability.dir(html_str)
      "ltr"

  """
  @spec dir(binary | html_tree) :: binary | nil
  def dir(raw_html) when is_binary(raw_html) do
    raw_html
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
    |> dir()
  end

  def dir(html_tree), do: MetadataFinder.dir(html_tree)

  @doc """
  Using a variety of metrics (content score, classname, element types), find the content that is
  most likely to be the stuff a user wants to read.

  ## Example

      iex> article_tree = Redability(html_str)
      # returns article that is tuple

  """
  @spec article(binary, options) :: html_tree
  def article(raw_html, opts \\ []) do
    opts = Keyword.merge(@default_options, opts)

    raw_html
    |> Helper.normalize()
    |> ArticleBuilder.build(opts)
  end

  @doc """
  Returns attributes, tags cleaned HTML.
  """
  @spec readable_html(html_tree) :: binary
  def readable_html(html_tree) do
    html_tree
    |> Helper.remove_attrs(regexes(:protect_attrs))
    |> raw_html()
  end

  @doc """
  Returns only text binary from `html_tree`.
  """
  @spec readable_text(html_tree) :: binary
  def readable_text(html_tree) do
    # @TODO: Remove image caption when extract only text
    tags_to_br = ~r/<\/(p|div|article|h\d)/i
    html_str = raw_html(html_tree)

    tags_to_br
    |> Regex.replace(html_str, &"\n#{&1}")
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end

  @doc """
  Returns raw HTML binary from `html_tree`.
  """
  @spec raw_html(html_tree) :: binary
  def raw_html(html_tree) when is_list(html_tree) do
    html_tree |> LazyHTML.from_tree() |> LazyHTML.to_html()
  end

  def raw_html(html_tree) when is_tuple(html_tree) do
    [html_tree] |> LazyHTML.from_tree() |> LazyHTML.to_html()
  end

  @deprecated "Use `LazyHTML.from_document/1` or `LazyHTML.from_fragment/1` instead."
  def parse(raw_html) when is_binary(raw_html) do
    raw_html |> LazyHTML.from_document() |> LazyHTML.to_tree()
  end

  def regexes(:unlikely_candidate),
    do:
      ~r/combx|comment|community|disqus|extra|foot|header|hidden|lightbox|modal|menu|meta|nav|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup/i

  def regexes(:ok_maybe_its_a_candidate), do: ~r/and|article|body|column|main|shadow/i

  def regexes(:positive), do: ~r/article|body|content|entry|hentry|main|page|pagination|post|text|blog|story/i

  def regexes(:negative),
    do:
      ~r/hidden|^hid|combx|comment|com-|contact|foot|footer|footnote|link|masthead|media|meta|outbrain|promo|related|scroll|shoutbox|sidebar|sponsor|shopping|tags|tool|utility|widget/i

  def regexes(:div_to_p_elements), do: ~r/<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i

  def regexes(:replace_brs), do: ~r/(<br[^>]*>[ \n\r\t]*){2,}/i

  def regexes(:replace_fonts), do: ~r/<(\/?)font[^>]*>/i

  def regexes(:replace_xml_version), do: ~r/<\?xml.*\?>/i

  def regexes(:normalize), do: ~r/\s{2,}/

  def regexes(:video), do: ~r/\/\/(www\.)?(dailymotion|youtube|youtube-nocookie|player\.vimeo)\.com/i

  def regexes(:protect_attrs), do: ~r/^(?!id|rel|for|summary|title|href|src|alt|srcdoc)/i

  def regexes(:img_tag_src), do: ~r/(<img.*src=['"])([^'"]+)(['"][^>]*>)/Ui

  def regexes(_key), do: nil

  def default_options, do: @default_options
end

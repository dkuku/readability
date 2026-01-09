defmodule Readability.MetadataFinder do
  @moduledoc """
  MetadataFinder extracts various metadata from HTML documents.
  Follows Mozilla Readability.js priority order for metadata extraction.
  """

  @type html_tree :: tuple | list

  # property pattern: matches patterns like:
  # - article:author, dc:title, og:description, twitter:title
  # - og:article:author, og:article:published_time (nested patterns)
  @property_pattern ~r/^\s*(article|dc|dcterm|og|twitter)\s*:\s*(?:article\s*:\s*)?(author|creator|description|published_time|title|site_name)\s*$/i

  # name pattern: (dc|dcterm|og|twitter|parsely|weibo:(article|webpage))[-.:](author|creator|pub-date|description|title|site_name)
  # Also matches "byl" (NYTimes byline) and standalone "author", "description", "title"
  @name_pattern ~r/^\s*(?:(dc|dcterm|og|twitter|parsely|weibo:(article|webpage))\s*[-\.:]?\s*)?(author|creator|pub-date|description|title|site_name|byl)\s*$/i

  # Title separators used by Mozilla Readability.js
  # Includes: | - – — \ / > »
  # Using Unicode codepoints for en-dash (U+2013) and em-dash (U+2014)
  @title_separators ~r/\s[\|\-\x{2013}\x{2014}\\\/\>\»]\s/u

  # JSON-LD article types from Mozilla Readability.js
  @json_ld_article_types ~r/^Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|AskPublicNewsArticle|BackgroundNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|Report|SatiricalArticle|ScholarlyArticle|MedicalScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference$/

  @doc """
  Extract JSON-LD metadata from script tags.
  Mozilla Readability.js gives precedence to Schema.org JSON-LD data.
  """
  @spec extract_json_ld(html_tree) :: map
  def extract_json_ld(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)
    scripts = lazy |> LazyHTML.query("script[type='application/ld+json']") |> LazyHTML.to_tree()

    Enum.find_value(scripts, %{}, fn script ->
      case script do
        {_, _, [content]} when is_binary(content) ->
          parse_json_ld(content)
        _ -> nil
      end
    end) || %{}
  end

  defp parse_json_ld(content) do
    content = String.replace(content, ~r/^\s*<!\[CDATA\[|\]\]>\s*$/, "")

    with {:ok, parsed} <- Jason.decode(content),
         %{} = article when article != nil <- find_article_in_json_ld(parsed) do
      extract_metadata_from_json_ld(article)
    else
      _ -> %{}
    end
  end

  defp find_article_in_json_ld(parsed) when is_list(parsed) do
    Enum.find(parsed, fn item ->
      type = item["@type"]
      type && Regex.match?(@json_ld_article_types, type)
    end)
  end
  defp find_article_in_json_ld(%{"@graph" => graph}) when is_list(graph) do
    find_article_in_json_ld(graph)
  end
  defp find_article_in_json_ld(%{"@type" => type} = parsed) do
    if Regex.match?(@json_ld_article_types, type || ""), do: parsed, else: nil
  end
  defp find_article_in_json_ld(_), do: nil

  defp extract_metadata_from_json_ld(parsed) do
    [
      {:title, extract_json_ld_title(parsed)},
      {:byline, extract_json_ld_byline(parsed)},
      {:excerpt, get_trimmed_string(parsed, "description")},
      {:site_name, get_in(parsed, ["publisher", "name"]) |> trim_if_binary()},
      {:published_time, get_trimmed_string(parsed, "datePublished")}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp extract_json_ld_title(parsed) do
    publisher_name = get_in(parsed, ["publisher", "name"]) |> trim_if_binary()
    name = get_trimmed_string(parsed, "name")
    headline = get_trimmed_string(parsed, "headline")

    cond do
      name && headline && publisher_name == name -> headline
      name -> name
      headline -> headline
      true -> nil
    end
  end

  defp extract_json_ld_byline(%{"author" => %{"name" => name}}) when is_binary(name) do
    String.trim(name)
  end

  defp extract_json_ld_byline(%{"author" => authors}) when is_list(authors) do
    authors
    |> Enum.map(&get_in(&1, ["name"]))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  defp extract_json_ld_byline(_), do: nil

  defp get_trimmed_string(map, key) do
    case map[key] do
      str when is_binary(str) and str != "" -> String.trim(str)
      _ -> nil
    end
  end

  defp trim_if_binary(str) when is_binary(str), do: String.trim(str)
  defp trim_if_binary(_), do: nil

  @doc """
  Extract all metadata values from meta tags into a map.
  This follows the Mozilla Readability.js pattern of collecting all values first.
  Handles space-separated property values (e.g., property="dc:title og:title").
  """
  @spec collect_meta_values(html_tree) :: map
  def collect_meta_values(html_tree) do
    meta_elements =
      html_tree
      |> LazyHTML.from_tree()
      |> LazyHTML.query("meta")
      |> LazyHTML.to_tree()

    meta_elements
    |> Enum.reduce(%{}, &collect_property_values/2)
    |> then(&Enum.reduce(meta_elements, &1, fn el, acc -> collect_name_values(el, acc) end))
  end

  defp collect_property_values({_, attrs, _}, acc) do
    attrs_map = Map.new(attrs)

    with content when content != "" <- attrs_map["content"] |> to_string() |> String.trim(),
         property when property != "" <- attrs_map["property"] || "" do
      property
      |> String.split(~r/\s+/)
      |> Enum.filter(&Regex.match?(@property_pattern, &1))
      |> Enum.reduce(acc, fn prop, inner_acc ->
        key = prop |> String.downcase() |> String.replace(~r/\s/, "") |> normalize_property_key()
        Map.put_new(inner_acc, key, content)
      end)
    else
      _ -> acc
    end
  end

  defp collect_property_values(_, acc), do: acc

  defp collect_name_values({_, attrs, _}, acc) do
    attrs_map = Map.new(attrs)

    with content when content != "" <- attrs_map["content"] |> to_string() |> String.trim(),
         name when name != "" <- attrs_map["name"] || "",
         true <- Regex.match?(@name_pattern, name) do
      key = name |> String.downcase() |> String.replace(~r/\s/, "") |> String.replace(".", ":")
      Map.put_new(acc, key, content)
    else
      _ -> acc
    end
  end

  defp collect_name_values(_, acc), do: acc

  @doc """
  Extract title following Mozilla Readability.js priority order:
  JSON-LD -> dc:title -> dcterm:title -> og:title -> weibo:article:title -> weibo:webpage:title -> title -> twitter:title -> parsely-title
  Falls back to _getArticleTitle() logic if none found.
  """
  @spec title(html_tree) :: binary | nil
  @title_keys ~w(dc:title dcterm:title og:title weibo:article:title weibo:webpage:title title twitter:title parsely-title)

  def title(html_tree) do
    html_tree
    |> extract_json_ld()
    |> Map.get(:title)
    |> case do
      nil -> html_tree |> collect_meta_values() |> first_matching_value(@title_keys)
      title -> title
    end
    |> unescape_html_entities()
  end

  defp first_matching_value(values, keys) do
    Enum.find_value(keys, fn key -> values[key] end)
  end

  @doc """
  Clean article title by stripping site name suffixes.
  Implements Mozilla Readability.js _getArticleTitle() logic.
  Only strips the LAST separator part when it looks like a site name.
  """
  @spec clean_title(binary, html_tree) :: binary
  def clean_title(nil, _html_tree), do: nil
  def clean_title("", _html_tree), do: ""

  def clean_title(title, _html_tree) do
    orig_title = String.trim(title)

    @title_separators
    |> Regex.split(orig_title)
    |> strip_site_name_suffix(orig_title)
    |> String.trim()
  end

  defp strip_site_name_suffix([_single], orig_title), do: orig_title

  defp strip_site_name_suffix(parts, orig_title) when length(parts) > 1 do
    last_word_count = parts |> List.last() |> word_count()

    if last_word_count > 4 do
      orig_title
    else
      candidate = parts |> Enum.drop(-1) |> Enum.join(" | ")
      first_removed = parts |> Enum.drop(1) |> Enum.join(" | ")

      cond do
        word_count(candidate) >= 3 -> candidate
        word_count(first_removed) > word_count(candidate) -> first_removed
        true -> orig_title
      end
    end
  end

  defp strip_site_name_suffix(_, orig_title), do: orig_title

  defp word_count(str) when is_binary(str) do
    str |> String.split(~r/\s+/) |> Enum.reject(&(&1 == "")) |> length()
  end
  defp word_count(_), do: 0

  @doc """
  Extract byline/author following Mozilla Readability.js priority order:
  JSON-LD -> dc:creator -> dcterm:creator -> author -> parsely-author -> article:author (if not URL)
  Also tries to extract from DOM elements with author-related attributes.
  """
  @spec byline(html_tree) :: binary | nil
  @byline_keys ~w(dc:creator dcterm:creator author parsely-author byl)

  def byline(html_tree) do
    html_tree
    |> extract_json_ld()
    |> Map.get(:byline)
    |> case do
      nil -> extract_byline_from_meta(html_tree)
      byline -> byline
    end
    |> unescape_html_entities()
  end

  defp extract_byline_from_meta(html_tree) do
    values = collect_meta_values(html_tree)

    article_author =
      case values["article:author"] do
        author when is_binary(author) -> unless is_url?(author), do: author
        _ -> nil
      end

    @byline_keys
    |> Enum.map(&values[&1])
    |> Kernel.++([article_author])
    |> Enum.find_value(&clean_byline/1)
    |> case do
      nil -> extract_byline_from_dom(html_tree)
      result -> result
    end
  end

  defp clean_byline(nil), do: nil
  defp clean_byline(""), do: nil

  defp clean_byline(byline) do
    byline
    |> String.trim()
    |> String.replace(~r/^By\s+/i, "")
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  @byline_selectors ~w(
    .author_byline .byline-name .byline
    [itemprop='author'][itemprop='name'] [itemprop='author'] [rel='author']
    .author-name .post-author .article-author .entry-author .author
    [class*='byline'] [class*='author']
  )

  defp extract_byline_from_dom(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)

    Enum.find_value(@byline_selectors, fn selector ->
      lazy
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> List.first()
      |> extract_valid_text(1, 150)
    end)
  end

  defp extract_valid_text(nil, _min, _max), do: nil

  defp extract_valid_text(node, min_len, max_len) do
    text = node |> extract_text_from_node() |> String.trim()
    len = String.length(text)

    cond do
      len < min_len -> nil
      max_len != :infinity and len >= max_len -> nil
      true -> text
    end
  end

  defp extract_text_from_node({"br", _, _}), do: "\n"
  defp extract_text_from_node({_, _, children}) do
    Enum.map_join(children, "", &extract_text_from_node/1)
  end
  defp extract_text_from_node(text) when is_binary(text), do: text
  defp extract_text_from_node(_), do: ""

  @doc """
  Extract excerpt/description following Mozilla Readability.js priority order:
  JSON-LD -> dc:description -> dcterm:description -> og:description -> weibo:article:description ->
  weibo:webpage:description -> description -> twitter:description
  Falls back to first paragraph of article content if no meta description.
  """
  @spec excerpt(html_tree) :: binary | nil
  @excerpt_keys ~w(dc:description dcterm:description og:description weibo:article:description weibo:webpage:description description twitter:description)

  def excerpt(html_tree) do
    html_tree
    |> extract_json_ld()
    |> Map.get(:excerpt)
    |> case do
      nil ->
        html_tree
        |> collect_meta_values()
        |> first_matching_value(@excerpt_keys)
        |> case do
          nil -> extract_excerpt_from_content(html_tree)
          result -> result
        end

      excerpt ->
        excerpt
    end
    |> unescape_html_entities()
  end

  @excerpt_selectors [
    "article p", "main p", ".content p", ".post-content p", ".entry-content p", "p",
    "article div", "main div", "div"
  ]

  defp extract_excerpt_from_content(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)

    Enum.find_value(@excerpt_selectors, fn selector ->
      lazy
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> Enum.find_value(&extract_valid_text(&1, 1, :infinity))
    end)
  end

  @doc """
  Extract site name from meta tags.
  Priority: JSON-LD -> og:site_name
  """
  @spec site_name(html_tree) :: binary | nil
  def site_name(html_tree) do
    html_tree
    |> extract_json_ld()
    |> Map.get(:site_name)
    |> case do
      nil -> html_tree |> collect_meta_values() |> Map.get("og:site_name")
      site_name -> site_name
    end
    |> unescape_html_entities()
  end

  @doc """
  Extract published time from meta tags.
  Priority: article:published_time -> parsely-pub-date
  """
  @spec published_time(html_tree) :: binary | nil
  @published_time_keys ~w(article:published_time parsely-pub-date)

  def published_time(html_tree) do
    html_tree
    |> collect_meta_values()
    |> first_matching_value(@published_time_keys)
    |> unescape_html_entities()
  end

  @doc """
  Extract language from html tag or meta tags.
  """
  @spec lang(html_tree) :: binary | nil
  def lang(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)

    get_first_attr(lazy, "html", "lang") ||
      get_first_attr(lazy, "meta[http-equiv='content-language']", "content")
  end

  @doc """
  Extract text direction from html, body, or article elements.
  Mozilla Readability.js checks ancestors of the article content.
  """
  @spec dir(html_tree) :: binary | nil
  @dir_selectors ~w(article body html)

  def dir(html_tree) do
    lazy = LazyHTML.from_tree(html_tree)
    Enum.find_value(@dir_selectors, &get_first_attr(lazy, &1, "dir"))
  end

  defp get_first_attr(lazy, selector, attr) do
    lazy
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(attr)
    |> List.first()
    |> case do
      nil -> nil
      "" -> nil
      value -> String.trim(value)
    end
  end

  defp normalize_property_key("og:article:" <> rest), do: "article:" <> rest
  defp normalize_property_key(key), do: key

  # Check if a string is a URL
  defp is_url?(str) when is_binary(str) do
    case URI.parse(str) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end
  defp is_url?(_), do: false

  # Unescape common HTML entities
  defp unescape_html_entities(nil), do: nil
  defp unescape_html_entities(str) when is_binary(str) do
    str
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> unescape_numeric_entities()
  end

  defp unescape_numeric_entities(str) do
    # Handle &#xHEX; entities
    str = Regex.replace(~r/&#x([0-9a-fA-F]+);/, str, fn full_match, hex ->
      case Integer.parse(hex, 16) do
        {num, _} when num > 0 and num <= 0x10FFFF ->
          try do
            <<num::utf8>>
          rescue
            _ -> full_match
          end
        _ -> full_match
      end
    end)

    # Handle &#DEC; entities
    Regex.replace(~r/&#([0-9]+);/, str, fn full_match, dec ->
      case Integer.parse(dec) do
        {num, _} when num > 0 and num <= 0x10FFFF ->
          try do
            <<num::utf8>>
          rescue
            _ -> full_match
          end
        _ -> full_match
      end
    end)
  end
end

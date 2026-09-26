defmodule Readability.MetadataFinder do
  @moduledoc """
  MetadataFinder extracts various metadata from HTML documents.
  Follows Mozilla Readability.js priority order for metadata extraction.
  """

  @type html_tree :: tuple | list
  @type lazy :: LazyHTML.t()

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
  @spec extract_json_ld(lazy) :: map
  def extract_json_ld(lazy) do
    lazy
    |> LazyHTML.query("script[type='application/ld+json']")
    |> LazyHTML.to_tree()
    |> Enum.find_value(%{}, fn script ->
      case script do
        {_, _, [content]} when is_binary(content) ->
          case parse_json_ld(content) do
            %{} = result when map_size(result) > 0 -> result
            _ -> nil
          end

        _ ->
          nil
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
    # First try to find Article type specifically
    article_specific =
      Enum.find(parsed, fn item ->
        type = item["@type"]
        type && type == "Article"
      end)

    if article_specific,
      do: article_specific,
      # Fall back to any article type
      else:
        Enum.find(parsed, fn item ->
          type = item["@type"]
          type && Regex.match?(@json_ld_article_types, type)
        end)
  end

  defp find_article_in_json_ld(%{"@graph" => graph}) when is_list(graph) do
    find_article_in_json_ld(graph)
  end

  defp find_article_in_json_ld(%{"@type" => type} = parsed) do
    if Regex.match?(@json_ld_article_types, type || ""), do: parsed
  end

  defp find_article_in_json_ld(_), do: nil

  defp extract_metadata_from_json_ld(parsed) do
    [
      {:title, extract_json_ld_title(parsed)},
      {:byline, extract_json_ld_byline(parsed)},
      {:excerpt, get_trimmed_string(parsed, "description")},
      {:site_name, extract_publisher_name(parsed)},
      {:published_time, get_trimmed_string(parsed, "datePublished")}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp extract_json_ld_title(parsed) do
    publisher_name = extract_publisher_name(parsed)
    name = get_trimmed_string(parsed, "name")
    headline = get_trimmed_string(parsed, "headline")

    cond do
      name && headline && publisher_name == name -> headline
      name -> name
      headline -> headline
      true -> nil
    end
  end

  defp extract_publisher_name(parsed) do
    case parsed["publisher"] do
      %{"name" => name} when is_binary(name) -> String.trim(name)
      [%{"name" => name} | _] when is_binary(name) -> String.trim(name)
      _ -> nil
    end
  end

  defp extract_json_ld_byline(%{"author" => %{"name" => name}}) when is_binary(name) do
    String.trim(name)
  end

  defp extract_json_ld_byline(%{"author" => authors}) when is_list(authors) do
    authors
    |> Enum.map(&get_in(&1, ["name"]))
    |> Enum.filter(&is_binary/1)
    |> Enum.map_join(", ", &String.trim/1)
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

  @doc """
  Extract all metadata values from meta tags into a map.
  This follows the Mozilla Readability.js pattern of collecting all values first.
  Handles space-separated property values (e.g., property="dc:title og:title").
  """
  @spec collect_meta_values(html_tree) :: map
  def collect_meta_values(lazy) do
    meta_elements =
      lazy
      |> LazyHTML.query("meta")
      |> LazyHTML.to_tree()

    # Process all meta elements using for comprehension
    for meta_element <- meta_elements, reduce: %{} do
      acc ->
        case meta_element do
          {_, attrs, _} ->
            attrs_map = Map.new(attrs)
            content = attrs_map["content"] || ""
            property = attrs_map["property"] || ""
            name = attrs_map["name"] || ""

            cond do
              # Process property-based meta tags
              property != "" && content != "" ->
                property
                |> String.split(~r/\s+/)
                |> Enum.filter(&Regex.match?(@property_pattern, &1))
                |> Enum.reduce(acc, fn prop, inner_acc ->
                  key = prop |> String.downcase() |> String.replace(~r/\s/, "") |> normalize_property_key()
                  Map.put_new(inner_acc, key, String.trim(content))
                end)

              # Process name-based meta tags
              name != "" && content != "" && Regex.match?(@name_pattern, name) ->
                key = name |> String.downcase() |> String.replace(~r/\s/, "") |> String.replace(".", ":")
                Map.put_new(acc, key, String.trim(content))

              true ->
                acc
            end

          _ ->
            acc
        end
    end
  end

  @doc """
  Extract title following Mozilla Readability.js priority order:
  JSON-LD -> dc:title -> dcterm:title -> og:title -> weibo:article:title -> weibo:webpage:title -> title -> twitter:title -> parsely-title
  Falls back to _getArticleTitle() logic if none found.
  """
  @spec title(lazy) :: binary | nil
  @title_keys ~w(dc:title dcterm:title og:title weibo:article:title weibo:webpage:title title twitter:title parsely-title)

  def title(lazy) do
    lazy
    |> extract_json_ld()
    |> Map.get(:title)
    |> case do
      nil -> lazy |> collect_meta_values() |> first_matching_value(@title_keys)
      title -> title
    end
    |> normalize_whitespace()
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
  @spec byline(lazy) :: binary | nil
  @byline_keys ~w(dc:creator dcterm:creator author parsely-author byl)

  def byline(lazy) do
    lazy
    |> extract_json_ld()
    |> Map.get(:byline)
    |> case do
      nil -> extract_byline_from_meta(lazy)
      byline -> byline
    end
    |> unescape_html_entities()
  end

  defp extract_byline_from_meta(lazy) do
    values = collect_meta_values(lazy)

    article_author =
      case values["article:author"] do
        author when is_binary(author) -> if !is_url?(author), do: author
        _ -> nil
      end

    @byline_keys
    |> Enum.map(&values[&1])
    |> Kernel.++([article_author])
    |> Enum.find_value(&clean_byline/1)
    |> case do
      nil -> extract_byline_from_dom(lazy)
      result -> result
    end
  end

  defp clean_byline(nil), do: nil
  defp clean_byline(""), do: nil

  defp clean_byline(byline) do
    trimmed = String.trim(byline)

    # Only strip "By " if it's a simple byline (no newlines, not too long)
    cleaned =
      if String.contains?(trimmed, "\n") or String.length(trimmed) > 100 do
        trimmed
      else
        String.replace(trimmed, ~r/^By\s+/i, "")
      end

    case cleaned do
      "" -> nil
      result -> result
    end
  end

  # Mozilla Readability extracts byline during article parsing from nodes with
  # rel="author" or itemprop containing "author", checking for [itemprop="name"] child.
  # We use a conservative subset of selectors to avoid false positives.
  @byline_selectors [
    "[itemprop='author'] [itemprop='name']",
    "[itemprop='author']",
    "[rel='author']",
    ".byline [itemprop='name']",
    ".byline-name",
    ".byline",
    ".author",
    ".author-name",
    "[class*='author']",
    "[class*='byline']",
    "[class*='writer']"
  ]

  defp extract_byline_from_dom(lazy) do
    Enum.find_value(@byline_selectors, fn selector ->
      lazy
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> List.first()
      |> extract_valid_text(1, 100)
      |> clean_byline_text()
    end)
  end

  # Clean byline text by removing common prefixes and trailing punctuation
  defp clean_byline_text(nil), do: nil

  defp clean_byline_text(text) do
    text
    |> String.replace(~r/^(by|por|von|par)\s+/i, "")
    |> String.replace(~r/[\s\p{Pd}—–]+$/u, "")
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
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
  rescue
    _ -> ""
  end

  defp extract_text_from_node(text) when is_binary(text), do: text
  defp extract_text_from_node(_), do: ""

  @doc """
  Extract excerpt/description following Mozilla Readability.js priority order:
  JSON-LD -> dc:description -> dcterm:description -> og:description -> weibo:article:description ->
  weibo:webpage:description -> description -> twitter:description
  Falls back to first paragraph of article content if no meta description.
  """
  @spec excerpt(lazy) :: binary | nil
  @excerpt_keys ~w(dc:description dcterm:description og:description weibo:article:description weibo:webpage:description description twitter:description)

  def excerpt(lazy) do
    lazy
    |> extract_json_ld()
    |> Map.get(:excerpt)
    |> case do
      nil ->
        lazy
        |> collect_meta_values()
        |> first_matching_value(@excerpt_keys)
        |> case do
          nil -> extract_excerpt_from_content(lazy)
          result -> result
        end

      excerpt ->
        excerpt
    end
    |> normalize_whitespace()
    |> unescape_html_entities()
  end

  @excerpt_selectors [
    "article p",
    "main p",
    ".content p",
    ".post-content p",
    ".entry-content p",
    ".article-content p",
    ".post p",
    "[role='main'] p",
    "p",
    "article div",
    "main div",
    ".content div",
    "div"
  ]

  defp extract_excerpt_from_content(lazy) do
    # Try to find a good excerpt - prefer longer paragraphs (50-500 chars)
    # Fall back to shorter text if nothing found (10-500 chars)
    Enum.find_value(@excerpt_selectors, fn selector ->
      lazy
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> Enum.find_value(&extract_valid_text(&1, 50, 500))
    end) ||
      Enum.find_value(@excerpt_selectors, fn selector ->
        lazy
        |> LazyHTML.query(selector)
        |> LazyHTML.to_tree()
        |> Enum.find_value(&extract_valid_text(&1, 10, 500))
      end)
  end

  @doc """
  Extract site name from meta tags.
  Priority: JSON-LD -> og:site_name
  """
  @spec site_name(lazy) :: binary | nil
  def site_name(lazy) do
    lazy
    |> extract_json_ld()
    |> Map.get(:site_name)
    |> case do
      nil -> lazy |> collect_meta_values() |> Map.get("og:site_name")
      site_name -> site_name
    end
    |> unescape_html_entities()
  end

  @doc """
  Extract published time from meta tags.
  Priority: article:published_time -> parsely-pub-date
  """
  @spec published_time(lazy) :: binary | nil
  @published_time_keys ~w(article:published_time parsely-pub-date)

  def published_time(lazy) do
    lazy
    |> collect_meta_values()
    |> first_matching_value(@published_time_keys)
    |> unescape_html_entities()
  end

  @doc """
  Extract language from html tag or meta tags.
  """
  @spec lang(lazy) :: binary | nil
  def lang(lazy) do
    get_first_attr(lazy, "html", "lang") ||
      get_first_attr(lazy, "meta[http-equiv='content-language']", "content")
  end

  @doc """
  Extract text direction from html, body, or main elements.
  Mozilla Readability.js checks ancestors of the article content (not article itself).
  """
  @spec dir(lazy) :: binary | nil
  @dir_selectors ~w(main body html)

  def dir(lazy) do
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

  # Unicode replacement character for invalid codepoints
  @replacement_char "\uFFFD"

  defp unescape_numeric_entities(str) do
    # Handle &#xHEX; entities
    str =
      Regex.replace(~r/&#x([0-9a-fA-F]+);/, str, fn full_match, hex ->
        case Integer.parse(hex, 16) do
          {num, _} when num > 0 and num <= 0x10FFFF ->
            try do
              <<num::utf8>>
            rescue
              _ -> @replacement_char
            end

          {num, _} when num == 0 or num > 0x10FFFF ->
            # Invalid codepoint - use replacement character
            @replacement_char

          _ ->
            full_match
        end
      end)

    # Handle &#DEC; entities
    Regex.replace(~r/&#([0-9]+);/, str, fn full_match, dec ->
      case Integer.parse(dec) do
        {num, _} when num > 0 and num <= 0x10FFFF ->
          try do
            <<num::utf8>>
          rescue
            _ -> @replacement_char
          end

        {num, _} when num == 0 or num > 0x10FFFF ->
          # Invalid codepoint - use replacement character
          @replacement_char

        _ ->
          full_match
      end
    end)
  end

  # Normalize whitespace - collapse 3+ spaces into single space, preserve newlines and double spaces
  defp normalize_whitespace(nil), do: nil

  defp normalize_whitespace(str) when is_binary(str) do
    str
    # Replace 3+ non-newline whitespace with single space
    |> String.replace(~r/[^\S\n]{3,}/, " ")
    |> String.trim()
  end
end

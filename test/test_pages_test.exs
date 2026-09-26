defmodule TestPagesTest do
  use ExUnit.Case, async: true

  @test_pages_path "./test/mozilla_readability/test/test-pages/"

  @moduletag :integration

  @testcases @test_pages_path
             |> File.ls!()
             |> Enum.map(fn dir ->
               path = Path.join(@test_pages_path, dir)
               source_path = Path.join(path, "source.html")
               expected_path = Path.join(path, "expected.html")
               metadata_path = Path.join(path, "expected-metadata.json")

               %{
                 name: dir,
                 source: source_path,
                 expected_path: expected_path,
                 metadata_path: metadata_path
               }
             end)

  for %{
        name: dir,
        source: source_path,
        metadata_path: metadata_path,
        expected_path: expected_path
      } <- @testcases do
    @dir dir
    @source_path source_path
    @metadata_path metadata_path
    @expected_path expected_path
    describe "upstream page #{@dir}" do
      setup do
        source = File.read!(@source_path)

        [
          source: File.read!(@source_path),
          expected_metadata: Jason.decode!(File.read!(@metadata_path)),
          html_tree: Readability.Helper.normalize(source),
          expected_html: File.read!(@expected_path)
        ]
      end

      test "title", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_title = expected_metadata["title"] do
          actual_title = Readability.title(html_tree)
          assert actual_title == expected_title
        end
      end

      test "byline", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_byline = expected_metadata["byline"] do
          actual_byline = Readability.byline(html_tree)
          assert actual_byline == expected_byline
        end
      end

      test "site_name", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_site_name = expected_metadata["siteName"] do
          actual_site_name = Readability.site_name(html_tree)
          assert actual_site_name == expected_site_name
        end
      end

      test "lang", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_lang = expected_metadata["lang"] do
          actual_lang = Readability.lang(html_tree)
          assert actual_lang == expected_lang
        end
      end

      test "dir", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_dir = expected_metadata["dir"] do
          actual_dir = Readability.dir(html_tree)
          assert actual_dir == expected_dir
        end
      end

      test "excerpt", %{expected_metadata: expected_metadata, html_tree: html_tree} do
        if expected_text = extract_text(expected_metadata["excerpt"]) do
          actual_excerpt = Readability.excerpt(html_tree)
          actual_text = extract_text(actual_excerpt)

          # Calculate similarity - we expect at least 50% text overlap
          similarity = text_similarity(expected_text, actual_text)

          assert similarity >= 0.5,
                 "Excerpt text similarity too low: #{Float.round(similarity * 100, 1)}%\n" <>
                   "Expected length: #{String.length(expected_text)}, Actual length: #{String.length(actual_text)}"
        end
      end

      test "readable_html", %{expected_html: expected_html, html_tree: html_tree} do
        article_tree = Readability.ArticleBuilder.build(html_tree, Readability.default_options())
        actual_html = Readability.readable_html(article_tree)

        # Compare normalized text content (ignoring HTML structure differences)
        expected_text = extract_text(expected_html)
        actual_text = extract_text(actual_html)

        # Calculate similarity - we expect at least 50% text overlap
        similarity = text_similarity(expected_text, actual_text)

        assert similarity >= 0.5,
               "Article text similarity too low: #{Float.round(similarity * 100, 1)}%\n" <>
                 "Expected length: #{String.length(expected_text)}, Actual length: #{String.length(actual_text)}"
      end
    end
  end

  # Extract and normalize text content from HTML
  defp extract_text(nil), do: ""

  defp extract_text(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Calculate Jaccard similarity between two texts based on word sets
  defp text_similarity(text1, text2) do
    words1 = text1 |> String.downcase() |> String.split(~r/\W+/, trim: true) |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split(~r/\W+/, trim: true) |> MapSet.new()

    intersection = words1 |> MapSet.intersection(words2) |> MapSet.size()
    union = words1 |> MapSet.union(words2) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end
end

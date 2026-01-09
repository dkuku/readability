defmodule TestPagesTest do
  use ExUnit.Case, async: true

  @test_pages_path "./test/mozilla_readability/test/test-pages/"

  @moduletag :integration

  @testcases @test_pages_path
             |> File.ls!()
             |> Enum.filter(&File.dir?(Path.join(@test_pages_path, &1)))
             |> Enum.map(fn dir ->
               path = Path.join(@test_pages_path, dir)
               source_path = Path.join(path, "source.html")
               expected_path = Path.join(path, "expected.html")
               metadata_path = Path.join(path, "expected-metadata.json")

               if File.exists?(source_path) and File.exists?(expected_path) and
                    File.exists?(metadata_path) do
                 %{
                   name: dir,
                   source: File.read!(source_path),
                   expected_html: File.read!(expected_path),
                   expected_metadata: Jason.decode!(File.read!(metadata_path))
                 }
               end
             end)
             |> Enum.reject(&is_nil/1)

  for %{name: dir, source: source, expected_metadata: expected_metadata} <- @testcases do
    @dir dir
    @source source
    @expected_metadata expected_metadata

    test "upstream page #{@dir}" do
      source = @source
      expected_metadata = @expected_metadata
      html_tree = Readability.Helper.normalize(source)

      expected_title = expected_metadata["title"]
      actual_title = Readability.title(html_tree)
      assert actual_title == expected_title
      expected_byline = expected_metadata["byline"]
      actual_byline = Readability.byline(html_tree)
      assert actual_byline == expected_byline

      # Test excerpt
      expected_excerpt = expected_metadata["excerpt"]
      actual_excerpt = Readability.excerpt(html_tree)
      assert actual_excerpt == expected_excerpt
      expected_site_name = expected_metadata["siteName"]
      actual_site_name = Readability.site_name(html_tree)
      assert actual_site_name == expected_site_name

      # Test lang
      expected_lang = expected_metadata["lang"]
      actual_lang = Readability.lang(html_tree)
      assert actual_lang == expected_lang

      # Test dir
      expected_dir = expected_metadata["dir"]
      actual_dir = Readability.dir(html_tree)
      assert actual_dir == expected_dir
    end
  end
end

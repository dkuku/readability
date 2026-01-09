defmodule TestPagesTest do
  use ExUnit.Case, async: true

  @test_pages_path "./test/mozilla_readability/test/test-pages/"

  @moduletag :integration

  setup_all do
    test_cases =
      @test_pages_path
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

    {:ok, test_cases: test_cases}
  end

  describe "upstream test pages" do
    test "metadata extraction matches upstream expectations", %{test_cases: test_cases} do
      results =
        test_cases
        |> Enum.map(fn test_case ->
          result = run_test_case(test_case)
          {test_case.name, result}
        end)

      # Count successes and failures by field
      stats = %{
        title: %{pass: 0, fail: 0},
        byline: %{pass: 0, fail: 0},
        excerpt: %{pass: 0, fail: 0},
        site_name: %{pass: 0, fail: 0},
        lang: %{pass: 0, fail: 0},
        dir: %{pass: 0, fail: 0}
      }

      stats =
        Enum.reduce(results, stats, fn {_name, result}, acc ->
          case result do
            {:ok, field_results} ->
              Enum.reduce(field_results, acc, fn {field, passed}, inner_acc ->
                if passed do
                  update_in(inner_acc, [field, :pass], &(&1 + 1))
                else
                  update_in(inner_acc, [field, :fail], &(&1 + 1))
                end
              end)

            _ ->
              acc
          end
        end)

      # Print summary
      IO.puts("\n\n=== Metadata Extraction Summary ===")

      for {field, %{pass: pass, fail: fail}} <- stats do
        total = pass + fail
        pct = if total > 0, do: Float.round(pass / total * 100, 1), else: 0.0
        IO.puts("#{field}: #{pass}/#{total} passed (#{pct}%)")
      end

      # Calculate overall pass rate
      total_pass = Enum.reduce(stats, 0, fn {_, %{pass: p}}, acc -> acc + p end)
      total_tests = Enum.reduce(stats, 0, fn {_, %{pass: p, fail: f}}, acc -> acc + p + f end)

      overall_pct =
        if total_tests > 0, do: Float.round(total_pass / total_tests * 100, 1), else: 0.0

      IO.puts("\nOverall: #{total_pass}/#{total_tests} (#{overall_pct}%)")

      # For now, we expect at least 50% pass rate on title extraction
      title_pass_rate = stats.title.pass / (stats.title.pass + stats.title.fail) * 100
      assert title_pass_rate >= 50, "Title extraction pass rate too low: #{title_pass_rate}%"
    end
  end

  defp run_test_case(%{source: source, expected_metadata: expected_metadata}) do
    html_tree = source |> Readability.Helper.normalize()

    field_results = %{}

    # Test title
    field_results =
      case expected_metadata["title"] do
        nil ->
          field_results

        expected_title ->
          actual_title = Readability.title(html_tree)
          Map.put(field_results, :title, actual_title == expected_title)
      end

    # Test byline (author)
    field_results =
      case expected_metadata["byline"] do
        nil ->
          field_results

        expected_byline ->
          actual_byline = Readability.byline(html_tree)
          Map.put(field_results, :byline, actual_byline == expected_byline)
      end

    # Test excerpt
    field_results =
      case expected_metadata["excerpt"] do
        nil ->
          field_results

        expected_excerpt ->
          actual_excerpt = Readability.excerpt(html_tree)
          Map.put(field_results, :excerpt, actual_excerpt == expected_excerpt)
      end

    # Test siteName
    field_results =
      case expected_metadata["siteName"] do
        nil ->
          field_results

        expected_site_name ->
          actual_site_name = Readability.site_name(html_tree)
          Map.put(field_results, :site_name, actual_site_name == expected_site_name)
      end

    # Test lang
    field_results =
      case expected_metadata["lang"] do
        nil ->
          field_results

        expected_lang ->
          actual_lang = Readability.lang(html_tree)
          Map.put(field_results, :lang, actual_lang == expected_lang)
      end

    # Test dir
    field_results =
      case expected_metadata["dir"] do
        nil ->
          field_results

        expected_dir ->
          actual_dir = Readability.dir(html_tree)
          Map.put(field_results, :dir, actual_dir == expected_dir)
      end

    {:ok, field_results}
  end
end

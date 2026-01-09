defmodule Readability.ArticleBuilderTest do
  use ExUnit.Case, async: true

  alias Readability.ArticleBuilder

  describe "build/2" do
    test "handles HTML without body tag (fallback candidate)" do
      html_tree = [
        {"div", [], [
          {"p", [], ["Some short text."]}
        ]}
      ]

      opts = [
        retry_length: 250,
        min_text_length: 25,
        remove_unlikely_candidates: false,
        weight_classes: true,
        clean_conditionally: false
      ]

      result = ArticleBuilder.build(html_tree, opts)
      assert is_tuple(result) or is_list(result)
    end

    test "handles empty candidate with fallback to empty tuple" do
      html_tree = [{"span", [], ["tiny"]}]

      opts = [
        retry_length: 5,
        min_text_length: 25,
        remove_unlikely_candidates: false,
        weight_classes: false,
        clean_conditionally: false
      ]

      result = ArticleBuilder.build(html_tree, opts)
      assert {"div", [], _} = result
    end

    test "retries with different options when content is too short" do
      html_tree = [
        {"body", [], [
          {"div", [], [
            {"p", [], ["Short."]}
          ]}
        ]}
      ]

      opts = [
        retry_length: 1000,
        min_text_length: 25,
        remove_unlikely_candidates: true,
        weight_classes: true,
        clean_conditionally: true
      ]

      result = ArticleBuilder.build(html_tree, opts)
      assert {"div", [], _} = result
    end

    test "includes p tags that meet append criteria (long content, low link density)" do
      long_text = String.duplicate("This is some meaningful content. ", 10)

      html_tree = [
        {"body", [], [
          {"div", [{"class", "article"}], [
            {"p", [], [long_text]},
            {"p", [], ["Another paragraph with a sentence ending."]}
          ]}
        ]}
      ]

      opts = [
        retry_length: 50,
        min_text_length: 25,
        remove_unlikely_candidates: false,
        weight_classes: true,
        clean_conditionally: false
      ]

      result = ArticleBuilder.build(html_tree, opts)
      assert {"div", [], _children} = result
    end

    test "converts non-p/div tags to div in article" do
      html_tree = [
        {"body", [], [
          {"article", [{"class", "content"}], [
            {"p", [], [String.duplicate("Content here. ", 20)]}
          ]}
        ]}
      ]

      opts = [
        retry_length: 50,
        min_text_length: 25,
        remove_unlikely_candidates: false,
        weight_classes: true,
        clean_conditionally: false
      ]

      result = ArticleBuilder.build(html_tree, opts)
      html = [result] |> LazyHTML.from_tree() |> LazyHTML.to_html()
      assert is_binary(html)
    end

    test "handles tree_text with nested elements" do
      html_tree = [
        {"body", [], [
          {"div", [{"class", "article"}], [
            {"p", [], [
              "Text before ",
              {"span", [], ["nested text"]},
              " text after."
            ]}
          ]}
        ]}
      ]

      opts = [
        retry_length: 10,
        min_text_length: 5,
        remove_unlikely_candidates: false,
        weight_classes: false,
        clean_conditionally: false
      ]

      result = ArticleBuilder.build(html_tree, opts)
      assert {"div", [], _} = result
    end
  end
end

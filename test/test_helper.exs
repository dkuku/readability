defmodule TestHelper do
  @fixtures_path "./test/fixtures/"

  def read_fixture(file_name) do
    {:ok, html} = File.read(@fixtures_path <> file_name)
    html
  end

  def read_parse_fixture(file_name) do
    file_name
    |> read_fixture()
    |> LazyHTML.from_document()
    |> LazyHTML.to_tree()
  end
end

ExUnit.start()

defmodule DomexWeb.ErrorJSONTest do
  use DomexWeb.ConnCase, async: true

  test "renders 404" do
    assert DomexWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert DomexWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end

defmodule DomexWeb.PageController do
  use DomexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule PearviewWeb.PageController do
  use PearviewWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule PearviewWeb.Router do
  use PearviewWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PearviewWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PearviewWeb do
    pipe_through :browser

    get "/", ItemController, :index
    post "/items", ItemController, :create
    get "/items/:id", ItemController, :show
    get "/items/:id/edit", ItemController, :edit
    patch "/items/:id", ItemController, :update
    delete "/items/:id", ItemController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", PearviewWeb do
  #   pipe_through :api
  # end
end

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
    patch "/items/:id", ItemController, :update
    patch "/items/:id/cycle", ItemController, :cycle
    delete "/items/:id", ItemController, :delete

    get "/shopper", ShopperController, :index
    patch "/shopper/items/:id/cycle", ShopperController, :cycle
    post "/shopper/trip/end", ShopperController, :end_trip

    get "/manage", ManageController, :index
    post "/manage/stores", ManageController, :create_store
    patch "/manage/stores/:id", ManageController, :update_store
    delete "/manage/stores/:id", ManageController, :delete_store

    get "/manage/sections", ManageController, :sections
    post "/manage/stores/:store_id/sections", ManageController, :create_section
    patch "/manage/sections/:id", ManageController, :update_section
    patch "/manage/sections/:id/move", ManageController, :move_section
    delete "/manage/sections/:id", ManageController, :delete_section
  end

  # Other scopes may use custom stacks.
  # scope "/api", PearviewWeb do
  #   pipe_through :api
  # end
end

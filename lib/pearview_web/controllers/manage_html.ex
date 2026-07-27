defmodule PearviewWeb.ManageHTML do
  @moduledoc """
  This module contains pages rendered by ManageController.

  See the `manage_html` directory for all templates available.
  """
  use PearviewWeb, :html

  embed_templates "manage_html/*"
end

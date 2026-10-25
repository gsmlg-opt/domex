defmodule DomexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DomexWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil, doc: "the current scope"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-full bg-surface text-on-surface">
      <header class="appbar appbar-sticky appbar-primary px-4 sm:px-6">
        <div class="flex shrink-0 items-center gap-3">
          <a href={~p"/"} class="appbar-brand flex items-center gap-2 no-underline text-on-primary">
            <.dm_mdi name="home-automation" class="size-7" />
            <span class="appbar-title text-xl font-bold tracking-tight">Domex</span>
          </a>
          <.dm_badge variant="secondary" size="sm" pill class="font-medium">
            Local Hub
          </.dm_badge>
        </div>

        <div class="appbar-trailing flex items-center gap-3 ml-auto">
          <.link
            id="nav-sensors"
            navigate={~p"/sensors"}
            class="rounded-lg px-3 py-2 text-sm font-semibold text-on-primary transition-colors hover:bg-on-primary/10"
          >
            System sensors
          </.link>
          <a
            :if={Hologram.enabled?()}
            id="nav-hologram"
            href="/hologram"
            class="rounded-lg px-3 py-2 text-sm font-semibold text-on-primary transition-colors hover:bg-on-primary/10"
          >
            Hub overview
          </a>
          <.dm_theme_switcher />
        </div>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8 max-w-7xl mx-auto">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with DuskMoon alerts.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-md">
      <%= for kind <- [:info, :error] do %>
        <%= if msg = Phoenix.Flash.get(@flash, kind) do %>
          <.dm_alert
            variant={if kind == :error, do: "error", else: "info"}
            class="shadow-lg cursor-pointer"
            phx-click={JS.push("lv:clear-flash", value: %{key: kind})}
          >
            <div class="flex items-center gap-2">
              <.dm_mdi
                name={if kind == :error, do: "alert-circle", else: "information"}
                class="size-5 shrink-0"
              />
              <span>{msg}</span>
            </div>
          </.dm_alert>
        <% end %>
      <% end %>
    </div>
    """
  end
end

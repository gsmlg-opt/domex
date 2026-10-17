defmodule DomexWeb.Components.LightControl do
  @moduledoc """
  Light control component for brightness, color temperature, and RGB selection using DuskMoon UI.
  """

  use Phoenix.Component
  use PhoenixDuskmoon.Component

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  def light_control(assigns) do
    ~H"""
    <.dm_card id={"light-#{@shadow.id}"} variant="bordered" class="p-5 space-y-6">
      <!-- Header & Power Toggle -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-warning text-on-warning shadow-md",
              else: "bg-surface-container-high text-on-surface-variant"
            )
          ]}>
            <.dm_mdi name="lightbulb-outline" class="size-6" />
          </div>
          <div>
            <h3 class="font-bold text-lg leading-tight text-on-surface">{@shadow.name}</h3>
            <div class="flex items-center gap-1.5 mt-0.5">
              <.dm_badge
                variant={if @shadow.online?, do: "success", else: "error"}
                size="xs"
                pill
              >
                {if @shadow.online?, do: "Online", else: "Offline"}
              </.dm_badge>
              <span class="text-xs text-on-surface-variant font-mono">
                {@shadow.host}:{@shadow.port}
              </span>
            </div>
          </div>
        </div>

        <.dm_btn
          id={"btn-toggle-light-#{@shadow.id}"}
          phx-click="toggle"
          phx-value-id={@shadow.id}
          phx-target={@target}
          disabled={!@shadow.online?}
          variant={if @shadow.power, do: "primary", else: "outline"}
          size="sm"
          class="min-w-16"
        >
          {if @shadow.power, do: "ON", else: "OFF"}
        </.dm_btn>
      </div>
      
    <!-- Brightness Slider -->
      <div class="space-y-2">
        <div class="flex justify-between items-center text-sm font-medium">
          <span class="flex items-center gap-1.5 text-on-surface-variant">
            <.dm_mdi name="white-balance-sunny" class="size-4" /> Brightness
          </span>
          <.dm_badge variant="secondary" size="xs">
            {to_string(@shadow.brightness || 100)}%
          </.dm_badge>
        </div>
        <form phx-change="set_brightness" phx-target={@target} id={"form-bright-#{@shadow.id}"}>
          <input type="hidden" name="device_id" value={@shadow.id} />
          <input
            type="range"
            min="1"
            max="100"
            name="brightness"
            value={@shadow.brightness || 100}
            disabled={!@shadow.online? || !@shadow.power}
            class="w-full accent-primary cursor-pointer disabled:opacity-40"
          />
        </form>
      </div>
      
    <!-- Color Temperature Slider -->
      <div class="space-y-2">
        <div class="flex justify-between items-center text-sm font-medium">
          <span class="flex items-center gap-1.5 text-on-surface-variant">
            <.dm_mdi name="fire" class="size-4" /> Color Temperature
          </span>
          <.dm_badge variant="secondary" size="xs">
            {to_string(@shadow.color_temp || 4000)}K
          </.dm_badge>
        </div>
        <form phx-change="set_color_temp" phx-target={@target} id={"form-ct-#{@shadow.id}"}>
          <input type="hidden" name="device_id" value={@shadow.id} />
          <input
            type="range"
            min="1700"
            max="6500"
            step="100"
            name="color_temp"
            value={@shadow.color_temp || 4000}
            disabled={!@shadow.online? || !@shadow.power}
            class="w-full accent-tertiary cursor-pointer disabled:opacity-40"
          />
        </form>
        <div class="flex justify-between text-xs text-on-surface-variant px-1">
          <span>Warm (1700K)</span>
          <span>Cool (6500K)</span>
        </div>
      </div>
      
    <!-- RGB Color Picker -->
      <div class="pt-2 border-t border-outline-variant flex items-center justify-between">
        <span class="text-sm font-medium text-on-surface-variant flex items-center gap-1.5">
          <.dm_mdi name="palette" class="size-4" /> Accent Color
        </span>
        <form
          phx-change="set_rgb"
          phx-target={@target}
          id={"form-rgb-#{@shadow.id}"}
          class="flex items-center gap-2"
        >
          <input type="hidden" name="device_id" value={@shadow.id} />
          <input
            type="color"
            name="rgb"
            value={format_rgb_hex(@shadow.rgb)}
            disabled={!@shadow.online? || !@shadow.power}
            class="size-8 rounded-lg cursor-pointer border border-outline-variant disabled:opacity-40 bg-transparent"
          />
        </form>
      </div>
    </.dm_card>
    """
  end

  defp format_rgb_hex(nil), do: "#ffffff"

  defp format_rgb_hex(rgb) when is_integer(rgb) do
    hex = Integer.to_string(rgb, 16) |> String.pad_leading(6, "0")
    "#" <> String.downcase(hex)
  end

  defp format_rgb_hex(str) when is_binary(str) do
    if String.starts_with?(str, "#"), do: str, else: "#" <> str
  end
end

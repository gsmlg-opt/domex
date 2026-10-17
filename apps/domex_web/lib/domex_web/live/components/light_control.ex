defmodule DomexWeb.Components.LightControl do
  @moduledoc """
  Light control component for brightness, color temperature, and RGB selection.
  """

  use Phoenix.Component
  import DomexWeb.CoreComponents

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  def light_control(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-md border border-base-200 rounded-xl p-5 space-y-6">
      <!-- Header & Power Toggle -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-warning text-warning-content shadow-lg shadow-warning/30",
              else: "bg-base-200 text-base-content/60"
            )
          ]}>
            <.icon name="hero-light-bulb" class="size-6" />
          </div>
          <div>
            <h3 class="font-bold text-lg leading-tight">{@shadow.name}</h3>
            <p class="text-xs text-base-content/60">
              {if @shadow.online?, do: "Online", else: "Offline"} &bull; {@shadow.host}:{@shadow.port}
            </p>
          </div>
        </div>

        <button
          phx-click="toggle"
          phx-value-id={@shadow.id}
          phx-target={@target}
          disabled={!@shadow.online?}
          class={[
            "btn btn-sm sm:btn-md rounded-full font-medium transition-all",
            if(@shadow.power,
              do: "btn-warning text-warning-content",
              else: "btn-outline border-base-300 hover:border-warning"
            )
          ]}
        >
          {if @shadow.power, do: "ON", else: "OFF"}
        </button>
      </div>
      
    <!-- Brightness Slider -->
      <div class="space-y-2">
        <div class="flex justify-between items-center text-sm font-medium">
          <span class="flex items-center gap-1.5 text-base-content/70">
            <.icon name="hero-sun" class="size-4" /> Brightness
          </span>
          <span class="badge badge-sm badge-neutral">{to_string(@shadow.brightness || 100)}%</span>
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
            class="range range-warning range-sm w-full cursor-pointer disabled:opacity-40"
          />
        </form>
      </div>
      
    <!-- Color Temperature Slider -->
      <div class="space-y-2">
        <div class="flex justify-between items-center text-sm font-medium">
          <span class="flex items-center gap-1.5 text-base-content/70">
            <.icon name="hero-fire" class="size-4" /> Color Temperature
          </span>
          <span class="badge badge-sm badge-neutral">{to_string(@shadow.color_temp || 4000)}K</span>
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
            class="range range-accent range-sm w-full cursor-pointer disabled:opacity-40"
          />
        </form>
        <div class="flex justify-between text-xs text-base-content/50 px-1">
          <span>Warm (1700K)</span>
          <span>Cool (6500K)</span>
        </div>
      </div>
      
    <!-- RGB Color Picker -->
      <div class="pt-2 border-t border-base-200 flex items-center justify-between">
        <span class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
          <.icon name="hero-swatch" class="size-4" /> Accent Color
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
            class="size-8 rounded-lg cursor-pointer border border-base-300 disabled:opacity-40"
          />
        </form>
      </div>
    </div>
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

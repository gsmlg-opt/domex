defmodule DomexWeb.Components.AcControl do
  @moduledoc """
  Air Conditioner / Climate control component using DuskMoon UI.
  """

  use Phoenix.Component
  use PhoenixDuskmoon.Component

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  @modes [
    {:cool, "snowflake", "Cool"},
    {:heat, "fire", "Heat"},
    {:auto, "autorenew", "Auto"},
    {:dry, "water-percent", "Dry"},
    {:fan, "fan", "Fan"}
  ]

  @fan_speeds [
    {:auto, "Auto"},
    {:silent, "Silent"},
    {:low, "Low"},
    {:medium, "Med"},
    {:high, "High"}
  ]

  def ac_control(assigns) do
    assigns = assign(assigns, modes: @modes, fan_speeds: @fan_speeds)

    ~H"""
    <.dm_card id={"ac-#{@shadow.id}"} variant="bordered" class="p-5 space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-info text-on-info shadow-md",
              else: "bg-surface-container-high text-on-surface-variant"
            )
          ]}>
            <.dm_mdi name="air-conditioner" class="size-6" />
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
          id={"btn-toggle-ac-#{@shadow.id}"}
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
      
    <!-- Temperature Dial / Controls -->
      <div class="flex items-center justify-between bg-surface-container-high rounded-2xl p-4">
        <!-- Decrement -->
        <.dm_btn
          id={"btn-temp-dec-#{@shadow.id}"}
          phx-click="change_temp"
          phx-value-id={@shadow.id}
          phx-value-delta="-1"
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power || (@shadow.ac_target_temp || 24.0) <= 16.0}
          variant="ghost"
          size="sm"
          shape="circle"
        >
          <.dm_mdi name="minus" class="size-5" />
        </.dm_btn>
        
    <!-- Temperature Display -->
        <div class="text-center">
          <div class="text-4xl font-black tracking-tight text-on-surface">
            {format_temp(@shadow.ac_target_temp || 24.0)}<span class="text-2xl font-normal text-on-surface-variant">°C</span>
          </div>
          <%= if @shadow.ac_temp do %>
            <div class="text-xs font-medium text-on-surface-variant mt-1 flex items-center justify-center gap-1">
              <.dm_mdi name="home-outline" class="size-3.5" />
              <span>Room: {format_temp(@shadow.ac_temp)}°C</span>
            </div>
          <% end %>
        </div>
        
    <!-- Increment -->
        <.dm_btn
          id={"btn-temp-inc-#{@shadow.id}"}
          phx-click="change_temp"
          phx-value-id={@shadow.id}
          phx-value-delta="1"
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power || (@shadow.ac_target_temp || 24.0) >= 30.0}
          variant="ghost"
          size="sm"
          shape="circle"
        >
          <.dm_mdi name="plus" class="size-5" />
        </.dm_btn>
      </div>
      
    <!-- Mode Selector -->
      <div class="space-y-1.5">
        <label class="text-xs font-semibold uppercase tracking-wider text-on-surface-variant">
          Operating Mode
        </label>
        <div class="grid grid-cols-5 gap-1 bg-surface-container-high p-1 rounded-xl">
          <%= for {mode, icon, label} <- @modes do %>
            <button
              type="button"
              phx-click="set_mode"
              phx-value-id={@shadow.id}
              phx-value-mode={to_string(mode)}
              phx-target={@target}
              disabled={!@shadow.online? || !@shadow.power}
              class={[
                "flex flex-col items-center py-2 px-1 rounded-lg text-xs font-medium transition-all disabled:opacity-40 cursor-pointer",
                if(@shadow.ac_mode == mode,
                  do: "bg-surface text-primary font-bold shadow-sm",
                  else: "text-on-surface-variant hover:text-on-surface"
                )
              ]}
            >
              <.dm_mdi name={icon} class="size-4 mb-0.5" />
              <span>{label}</span>
            </button>
          <% end %>
        </div>
      </div>
      
    <!-- Fan Speed Selector -->
      <div class="space-y-1.5">
        <label class="text-xs font-semibold uppercase tracking-wider text-on-surface-variant">
          Fan Speed
        </label>
        <div class="grid grid-cols-5 gap-1 bg-surface-container-high p-1 rounded-xl">
          <%= for {speed, label} <- @fan_speeds do %>
            <button
              type="button"
              phx-click="set_fan_speed"
              phx-value-id={@shadow.id}
              phx-value-speed={to_string(speed)}
              phx-target={@target}
              disabled={!@shadow.online? || !@shadow.power}
              class={[
                "py-1.5 rounded-lg text-xs font-medium transition-all text-center disabled:opacity-40 cursor-pointer",
                if(@shadow.ac_fan_speed == speed,
                  do: "bg-surface text-primary font-bold shadow-sm",
                  else: "text-on-surface-variant hover:text-on-surface"
                )
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>
      
    <!-- Swing Toggle -->
      <div class="pt-2 border-t border-outline-variant flex items-center justify-between">
        <span class="text-sm font-medium text-on-surface-variant">Vertical Air Swing</span>
        <.dm_btn
          id={"btn-swing-#{@shadow.id}"}
          phx-click="toggle_swing"
          phx-value-id={@shadow.id}
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power}
          variant={if @shadow.ac_swing_vertical, do: "primary", else: "outline"}
          size="xs"
        >
          {if @shadow.ac_swing_vertical, do: "Oscillating", else: "Fixed"}
        </.dm_btn>
      </div>
    </.dm_card>
    """
  end

  defp format_temp(nil), do: "24.0"
  defp format_temp(temp) when is_integer(temp), do: "#{temp}.0"
  defp format_temp(temp) when is_float(temp), do: :erlang.float_to_binary(temp, decimals: 1)
end

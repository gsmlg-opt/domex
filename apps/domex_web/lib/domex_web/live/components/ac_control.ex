defmodule DomexWeb.Components.AcControl do
  @moduledoc """
  Air Conditioner / Climate control component for target temperature, modes, fan speeds, and swing.
  """

  use Phoenix.Component
  import DomexWeb.CoreComponents

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  @modes [
    {:cool, "hero-sparkles", "Cool"},
    {:heat, "hero-fire", "Heat"},
    {:auto, "hero-arrow-path", "Auto"},
    {:dry, "hero-beaker", "Dry"},
    {:fan, "hero-bolt", "Fan"}
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
    <div class="card bg-base-100 shadow-md border border-base-200 rounded-xl p-5 space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-info text-info-content shadow-lg shadow-info/30",
              else: "bg-base-200 text-base-content/60"
            )
          ]}>
            <.icon name="hero-sun" class="size-6" />
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
              do: "btn-info text-info-content",
              else: "btn-outline border-base-300 hover:border-info"
            )
          ]}
        >
          {if @shadow.power, do: "ON", else: "OFF"}
        </button>
      </div>
      
    <!-- Temperature Dial / Controls -->
      <div class="flex items-center justify-between bg-base-200/50 rounded-2xl p-4">
        <!-- Decrement -->
        <button
          phx-click="change_temp"
          phx-value-id={@shadow.id}
          phx-value-delta="-1"
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power || (@shadow.ac_target_temp || 24.0) <= 16.0}
          class="btn btn-circle btn-ghost border border-base-300 hover:bg-base-100"
        >
          <.icon name="hero-minus" class="size-5" />
        </button>
        
    <!-- Temperature Display -->
        <div class="text-center">
          <div class="text-4xl font-black tracking-tight text-base-content">
            {format_temp(@shadow.ac_target_temp || 24.0)}<span class="text-2xl font-normal text-base-content/60">°C</span>
          </div>
          <%= if @shadow.ac_temp do %>
            <div class="text-xs font-medium text-base-content/60 mt-1 flex items-center justify-center gap-1">
              <.icon name="hero-home" class="size-3.5" />
              <span>Room: {format_temp(@shadow.ac_temp)}°C</span>
            </div>
          <% end %>
        </div>
        
    <!-- Increment -->
        <button
          phx-click="change_temp"
          phx-value-id={@shadow.id}
          phx-value-delta="1"
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power || (@shadow.ac_target_temp || 24.0) >= 30.0}
          class="btn btn-circle btn-ghost border border-base-300 hover:bg-base-100"
        >
          <.icon name="hero-plus" class="size-5" />
        </button>
      </div>
      
    <!-- Mode Selector -->
      <div class="space-y-1.5">
        <label class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          Operating Mode
        </label>
        <div class="grid grid-cols-5 gap-1 bg-base-200 p-1 rounded-xl">
          <%= for {mode, icon, label} <- @modes do %>
            <button
              phx-click="set_mode"
              phx-value-id={@shadow.id}
              phx-value-mode={to_string(mode)}
              phx-target={@target}
              disabled={!@shadow.online? || !@shadow.power}
              class={[
                "flex flex-col items-center py-2 px-1 rounded-lg text-xs font-medium transition-all disabled:opacity-40",
                if(@shadow.ac_mode == mode,
                  do: "bg-base-100 text-info font-bold shadow-sm",
                  else: "text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              <.icon name={icon} class="size-4 mb-0.5" />
              <span>{label}</span>
            </button>
          <% end %>
        </div>
      </div>
      
    <!-- Fan Speed Selector -->
      <div class="space-y-1.5">
        <label class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          Fan Speed
        </label>
        <div class="grid grid-cols-5 gap-1 bg-base-200 p-1 rounded-xl">
          <%= for {speed, label} <- @fan_speeds do %>
            <button
              phx-click="set_fan_speed"
              phx-value-id={@shadow.id}
              phx-value-speed={to_string(speed)}
              phx-target={@target}
              disabled={!@shadow.online? || !@shadow.power}
              class={[
                "py-1.5 rounded-lg text-xs font-medium transition-all text-center disabled:opacity-40",
                if(@shadow.ac_fan_speed == speed,
                  do: "bg-base-100 text-info font-bold shadow-sm",
                  else: "text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>
      
    <!-- Swing Toggle -->
      <div class="pt-2 border-t border-base-200 flex items-center justify-between">
        <span class="text-sm font-medium text-base-content/70">Vertical Air Swing</span>
        <button
          phx-click="toggle_swing"
          phx-value-id={@shadow.id}
          phx-target={@target}
          disabled={!@shadow.online? || !@shadow.power}
          class={[
            "btn btn-xs rounded-full",
            if(@shadow.ac_swing_vertical,
              do: "btn-info text-info-content",
              else: "btn-ghost border border-base-300"
            )
          ]}
        >
          {if @shadow.ac_swing_vertical, do: "Oscillating", else: "Fixed"}
        </button>
      </div>
    </div>
    """
  end

  defp format_temp(nil), do: "24.0"
  defp format_temp(temp) when is_integer(temp), do: "#{temp}.0"
  defp format_temp(temp) when is_float(temp), do: :erlang.float_to_binary(temp, decimals: 1)
end

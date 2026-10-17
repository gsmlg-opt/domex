defmodule DomexWeb.Components.GenericSwitch do
  @moduledoc """
  Generic switch and smart plug component using DuskMoon UI.
  """

  use Phoenix.Component
  use PhoenixDuskmoon.Component

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  def generic_switch(assigns) do
    ~H"""
    <.dm_card id={"switch-#{@shadow.id}"} variant="bordered" class="p-5 space-y-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-success text-on-success shadow-md",
              else: "bg-surface-container-high text-on-surface-variant"
            )
          ]}>
            <.dm_mdi name="power" class="size-6" />
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

      <div class="pt-3 border-t border-outline-variant flex items-center justify-between text-xs text-on-surface-variant">
        <span>Adapter: {display_adapter(@shadow.adapter)}</span>
        <span class="font-mono">ID: {@shadow.id}</span>
      </div>
    </.dm_card>
    """
  end

  defp display_adapter(mod) when is_atom(mod),
    do: mod |> to_string() |> String.split(".") |> List.last()

  defp display_adapter(str), do: to_string(str)
end

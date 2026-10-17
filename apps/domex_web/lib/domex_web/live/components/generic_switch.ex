defmodule DomexWeb.Components.GenericSwitch do
  @moduledoc """
  Generic switch and smart plug component.
  """

  use Phoenix.Component
  import DomexWeb.CoreComponents

  attr :shadow, Domex.Device.Shadow, required: true
  attr :target, :any, default: nil

  def generic_switch(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-md border border-base-200 rounded-xl p-5 space-y-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class={[
            "size-10 rounded-full flex items-center justify-center transition-colors",
            if(@shadow.power && @shadow.online?,
              do: "bg-success text-success-content shadow-lg shadow-success/30",
              else: "bg-base-200 text-base-content/60"
            )
          ]}>
            <.icon name="hero-power" class="size-6" />
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
              do: "btn-success text-success-content",
              else: "btn-outline border-base-300 hover:border-success"
            )
          ]}
        >
          {if @shadow.power, do: "ON", else: "OFF"}
        </button>
      </div>

      <div class="pt-3 border-t border-base-200 flex items-center justify-between text-xs text-base-content/60">
        <span>Adapter: {display_adapter(@shadow.adapter)}</span>
        <span>ID: {@shadow.id}</span>
      </div>
    </div>
    """
  end

  defp display_adapter(mod) when is_atom(mod),
    do: mod |> to_string() |> String.split(".") |> List.last()

  defp display_adapter(str), do: to_string(str)
end

defmodule DomexWeb.Hologram.HubPage do
  use Hologram.Page

  route "/hologram"
  layout DomexWeb.Hologram.Layout

  @impl true
  def init(_params, component, _server) do
    put_state(component, devices: device_snapshot(), status: :all)
  end

  @impl true
  def template do
    ~HOLO"""
    <div id="hologram-hub" class="space-y-8">
      <section class="flex flex-col justify-between gap-5 sm:flex-row sm:items-end" aria-labelledby="hologram-title">
        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-widest text-primary">Your home, at a glance</p>
          <h1 id="hologram-title" class="text-3xl font-bold tracking-tight sm:text-4xl">Hub overview</h1>
          <p class="text-sm text-on-surface-variant">A snapshot of the devices connected to your local hub.</p>
        </div>
        <button id="hologram-refresh" type="button" $click={command: :refresh} class="rounded-xl bg-primary px-5 py-3 text-sm font-semibold text-on-primary transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
          Refresh status
        </button>
      </section>

      <section class="grid grid-cols-1 gap-4 sm:grid-cols-3" aria-label="Device summary" aria-live="polite">
        <div class="rounded-2xl border border-outline-variant bg-surface-container p-6">
          <p class="text-sm text-on-surface-variant">Total devices</p>
          <p id="hologram-total" class="mt-3 text-4xl font-bold tracking-tight">{length(@devices)}</p>
        </div>
        <div class="rounded-2xl border border-outline-variant bg-surface-container p-6">
          <p class="text-sm text-on-surface-variant">Online</p>
          <p id="hologram-online-count" class="mt-3 text-4xl font-bold tracking-tight text-primary">{Enum.count(@devices, & &1.online?)}</p>
        </div>
        <div class="rounded-2xl border border-outline-variant bg-surface-container p-6">
          <p class="text-sm text-on-surface-variant">Offline</p>
          <p id="hologram-offline-count" class="mt-3 text-4xl font-bold tracking-tight">{Enum.count(@devices, &(!&1.online?))}</p>
        </div>
      </section>

      <section class="overflow-hidden rounded-2xl border border-outline-variant bg-surface-container" aria-labelledby="hologram-devices-title">
        <div class="flex flex-wrap items-center justify-between gap-4 border-b border-outline-variant p-5 sm:px-6">
          <h2 id="hologram-devices-title" class="text-lg font-semibold">Devices</h2>
          <div class="flex gap-1 rounded-xl bg-surface p-1" role="group" aria-label="Filter devices">
            <button id="hologram-filter-all" type="button" $click={:filter, status: :all} aria-pressed={@status == :all} class="rounded-lg px-4 py-2 text-sm font-medium transition-colors hover:bg-surface-container-high aria-pressed:bg-primary aria-pressed:text-on-primary focus-visible:outline-2 focus-visible:outline-primary">All devices</button>
            <button id="hologram-filter-online" type="button" $click={:filter, status: :online} aria-pressed={@status == :online} class="rounded-lg px-4 py-2 text-sm font-medium transition-colors hover:bg-surface-container-high aria-pressed:bg-primary aria-pressed:text-on-primary focus-visible:outline-2 focus-visible:outline-primary">Online only</button>
          </div>
        </div>
        <div id="hologram-devices" aria-live="polite">
          {%for device <- visible_devices(@devices, @status)}
            <div id={"hologram-device-#{device.id}"} class="flex items-center justify-between gap-4 border-b border-outline-variant px-5 py-5 last:border-b-0 sm:px-6">
              <div class="min-w-0">
                <p class="truncate font-semibold">{device.name}</p>
                <p class="mt-1 text-xs capitalize text-on-surface-variant">{device.type}</p>
              </div>
              <span class={if(device.online?, do: "shrink-0 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary", else: "shrink-0 rounded-full bg-surface px-3 py-1 text-xs font-medium text-on-surface-variant")}>
                {if(device.online?, do: "Online", else: "Offline")}
              </span>
            </div>
          {/for}
          {%if visible_devices(@devices, @status) == []}
            <div id="hologram-empty" class="px-6 py-16 text-center">
              <h3 class="text-lg font-semibold">{if(@devices == [], do: "Your home starts here", else: "No devices are online")}</h3>
              <p class="mx-auto mt-2 max-w-sm text-sm leading-6 text-on-surface-variant">{if(@devices == [], do: "Add a device from the dashboard to see it in your hub overview.", else: "Choose All devices to see your configured devices, or refresh their status.")}</p>
              <a id="hologram-empty-dashboard-link" href="/" class="mt-5 inline-block text-sm font-semibold text-primary transition-opacity hover:opacity-75">Open dashboard →</a>
            </div>
          {/if}
        </div>
      </section>
    </div>
    """
  end

  @impl true
  def action(:filter, %{status: status}, component) when status in [:all, :online] do
    put_state(component, :status, status)
  end

  def action(:receive_devices, %{devices: devices}, component) do
    put_state(component, :devices, devices)
  end

  @impl true
  def command(:refresh, _params, server) do
    put_action(server, :receive_devices, devices: device_snapshot())
  end

  defp device_snapshot do
    Domex.list_devices()
    |> Enum.map(&Map.take(&1, [:id, :name, :type, :online?]))
    |> Enum.sort_by(& &1.name)
  end

  defp visible_devices(devices, :all), do: devices
  defp visible_devices(devices, :online), do: Enum.filter(devices, & &1.online?)
end

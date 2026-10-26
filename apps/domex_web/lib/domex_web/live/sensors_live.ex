defmodule DomexWeb.SensorsLive do
  @moduledoc "Live system status from standalone MQTT sensors."
  use DomexWeb, :live_view

  alias Domex.Sensor.Store

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Store.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "System sensors")
     |> stream(:sensors, Store.list(), dom_id: &"sensor-#{&1.id}")}
  end

  @impl true
  def handle_info({:sensor_updated, sensor}, socket),
    do: {:noreply, stream_insert(socket, :sensors, sensor)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="sensors-page" class="space-y-8">
        <div class="flex flex-wrap items-end justify-between gap-5 border-b border-outline-variant pb-6">
          <div>
            <p class="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-primary">
              Connected devices
            </p>
            <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">System sensors</h1>
            <p class="mt-3 max-w-xl text-sm leading-6 text-on-surface-variant">
              A live view of your computers. CPU, memory, and traffic, reported directly from each device.
            </p>
          </div>
          <.link
            id="sensors-dashboard"
            navigate={~p"/"}
            class="rounded-xl border border-outline-variant px-4 py-2.5 text-sm font-medium transition-colors hover:bg-surface-container-high"
          >
            Device dashboard
          </.link>
        </div>

        <div id="sensors" phx-update="stream" class="space-y-6">
          <div
            id="sensors-empty"
            class="hidden rounded-2xl border border-dashed border-outline-variant px-6 py-20 text-center only:block"
          >
            <p class="text-xs font-semibold uppercase tracking-widest text-primary">
              Ready when you are
            </p>
            <h2 class="mt-3 text-xl font-semibold">Connect your first computer</h2>
            <p class="mx-auto mt-3 max-w-md text-sm leading-6 text-on-surface-variant">
              Start a Domex sensor on your Mac or Linux device and point its MQTT host to this hub. Its system status will appear here automatically.
            </p>
          </div>
          <div :for={{dom_id, sensor} <- @streams.sensors} id={dom_id}>
            <.sensor_card sensor={sensor} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :sensor, :map, required: true

  defp sensor_card(assigns) do
    assigns = assign(assigns, :sample, assigns.sensor.sample || %{})

    ~H"""
    <article class="overflow-hidden rounded-2xl border border-outline-variant bg-surface-container shadow-sm">
      <header class="flex flex-wrap items-center justify-between gap-4 border-b border-outline-variant px-5 py-5 sm:px-6">
        <div class="min-w-0">
          <h2 class="truncate text-xl font-semibold tracking-tight">{@sensor.name}</h2>
          <p class="mt-1 text-xs text-on-surface-variant">{@sensor.hostname} · {@sensor.platform}</p>
        </div>
        <span
          id={"sensor-availability-#{@sensor.id}"}
          class={[
            "inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-semibold",
            if(@sensor.online?,
              do: "bg-primary/10 text-primary",
              else: "bg-surface-container-high text-on-surface-variant"
            )
          ]}
        >
          <span class={[
            "size-1.5 rounded-full",
            if(@sensor.online?, do: "bg-primary", else: "bg-on-surface-variant/50")
          ]} />
          {if @sensor.online?, do: "Online", else: "Offline"}
        </span>
      </header>

      <div class="space-y-6 p-5 sm:p-6">
        <p
          :if={@sensor.error != ""}
          id={"sensor-error-#{@sensor.id}"}
          role="alert"
          class="rounded-xl bg-error/10 px-4 py-3 text-sm text-error"
        >
          {@sensor.error}
        </p>
        <div class="grid gap-6 lg:grid-cols-2">
          <section class="rounded-xl border border-outline-variant bg-surface p-5">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h3 class="text-sm font-medium text-on-surface-variant">CPU usage</h3>
                <p
                  id={"sensor-cpu-#{@sensor.id}"}
                  class="mt-2 text-4xl font-semibold tabular-nums tracking-tight"
                >
                  {percent(metric(@sample, "cpu", "total"))}
                </p>
              </div>
              <p class="max-w-48 text-right text-xs leading-5 text-on-surface-variant">
                {@sample["cpu_brand"]}<br />{@sample["model"]}
              </p>
            </div>
            <svg
              :if={@sensor.history != []}
              id={"sensor-history-#{@sensor.id}"}
              viewBox="0 0 240 60"
              role="img"
              aria-label="Recent CPU usage"
              class="mt-5 h-16 w-full overflow-visible text-primary"
              preserveAspectRatio="none"
            >
              <polyline
                points={cpu_points(@sensor.history)}
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                vector-effect="non-scaling-stroke"
                stroke-linejoin="round"
              />
            </svg>
            <div
              id={"sensor-cores-#{@sensor.id}"}
              class="mt-4 grid grid-cols-2 gap-x-5 gap-y-3 sm:grid-cols-4"
            >
              <div :for={core <- @sample["cores"] || []} class="space-y-1.5">
                <p class="flex justify-between gap-2 text-[11px] text-on-surface-variant">
                  <span>Core {core["id"]}</span><span class="tabular-nums">{percent(core["total"])}</span>
                </p>
                <div class="h-1 overflow-hidden rounded-full bg-surface-container-high">
                  <div
                    class="h-full rounded-full bg-primary transition-all duration-500"
                    style={"width: #{bounded(core["total"])}%"}
                  />
                </div>
                <p :if={core["type"]} class="text-[10px] capitalize text-on-surface-variant">
                  {core["type"]}
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-xl border border-outline-variant bg-surface p-5">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h3 class="text-sm font-medium text-on-surface-variant">Memory usage</h3>
                <p
                  id={"sensor-memory-#{@sensor.id}"}
                  class="mt-2 text-4xl font-semibold tabular-nums tracking-tight"
                >
                  {percent(metric(@sample, "memory", "percent"))}
                </p>
              </div>
              <p class="text-right text-xs leading-5 text-on-surface-variant">
                {bytes(metric(@sample, "memory", "used"))} used<br />of {bytes(
                  metric(@sample, "memory", "physical")
                )}
              </p>
            </div>
            <div class="my-6 h-2 overflow-hidden rounded-full bg-surface-container-high">
              <div
                class="h-full rounded-full bg-primary transition-all duration-500"
                style={"width: #{bounded(metric(@sample, "memory", "percent"))}%"}
              />
            </div>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-xs sm:grid-cols-3">
              <div :for={
                {label, key} <- [
                  {"App", "app"},
                  {"Wired", "wired"},
                  {"Compressed", "compressed"},
                  {"Cached", "cached"},
                  {"Swap used", "swap_used"}
                ]
              }>
                <dt class="text-on-surface-variant">{label}</dt><dd class="mt-1 font-medium tabular-nums">
                  {bytes(metric(@sample, "memory", key))}
                </dd>
              </div>
              <div>
                <dt class="text-on-surface-variant">Pressure</dt><dd class="mt-1 font-medium">
                  {pressure(metric(@sample, "memory", "pressure"))}
                </dd>
              </div>
            </dl>
          </section>
        </div>

        <dl class="grid grid-cols-2 gap-5 border-t border-outline-variant pt-5 sm:grid-cols-4">
          <div :for={
            {label, group, key} <- [
              {"Disk read", "disk", "read_bps"},
              {"Disk write", "disk", "write_bps"},
              {"Network in", "network", "rx_bps"},
              {"Network out", "network", "tx_bps"}
            ]
          }>
            <dt class="text-xs text-on-surface-variant">{label}</dt><dd class="mt-2 text-lg font-semibold tabular-nums">
              {rate(metric(@sample, group, key))}
            </dd>
          </div>
        </dl>
        <div class="flex flex-wrap justify-between gap-3 border-t border-outline-variant pt-4 text-xs text-on-surface-variant">
          <p>
            {count(@sample["processes"])} processes · {count(@sample["threads"])} threads{if @sample[
                                                                                               "threads_complete"
                                                                                             ] ==
                                                                                               false,
                                                                                             do:
                                                                                               " (partial)"}
          </p>
          <p :for={gpu <- @sample["gpu"] || []}>{gpu["name"]} · GPU {percent(gpu["utilization"])}</p>
          <p>
            {status(@sensor)} · {if @sensor.updated_at,
              do: Calendar.strftime(@sensor.updated_at, "%H:%M:%S UTC"),
              else: "Waiting for a sample"}
          </p>
        </div>
      </div>
    </article>
    """
  end

  defp metric(sample, group, key), do: get_in(sample, [group, key])
  defp percent(value) when is_number(value), do: "#{Float.round(value / 1, 1)}%"
  defp percent(_), do: "—"
  defp bounded(value) when is_number(value), do: min(max(value, 0), 100)
  defp bounded(_), do: 0

  defp bytes(value) when is_number(value) and value >= 0 do
    {scale, unit} =
      Enum.find(
        [
          {1_099_511_627_776, "TiB"},
          {1_073_741_824, "GiB"},
          {1_048_576, "MiB"},
          {1_024, "KiB"},
          {1, "B"}
        ],
        fn {scale, _} -> value >= scale end
      ) || {1, "B"}

    "#{Float.round(value / scale, 1)} #{unit}"
  end

  defp bytes(_), do: "—"
  defp rate(value) when is_number(value), do: bytes(value) <> "/s"
  defp rate(_), do: "—"
  defp count(value) when is_integer(value), do: Integer.to_string(value)
  defp count(_), do: "—"
  defp pressure(1), do: "Normal"
  defp pressure(2), do: "Elevated"
  defp pressure(4), do: "Critical"
  defp pressure(_), do: "—"
  defp status(%{online?: false}), do: "Last reported values"
  defp status(%{status: "warming"}), do: "Warming up"
  defp status(%{status: "error"}), do: "Collector error"
  defp status(_), do: "Live"

  defp cpu_points(history) do
    width = max(length(history) - 1, 1)

    history
    |> Enum.with_index()
    |> Enum.flat_map(fn {sample, index} ->
      case metric(sample, "cpu", "total") do
        value when is_number(value) ->
          ["#{Float.round(index / width * 240, 2)},#{Float.round(60 - bounded(value) * 0.6, 2)}"]

        _ ->
          []
      end
    end)
    |> Enum.join(" ")
  end
end

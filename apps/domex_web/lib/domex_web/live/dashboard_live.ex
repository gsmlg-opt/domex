defmodule DomexWeb.DashboardLive do
  @moduledoc """
  All-device control dashboard with real-time PubSub synchronization.
  """

  use DomexWeb, :live_view

  alias Domex.Device.Shadow
  alias Domex.PubSub
  import DomexWeb.Components.LightControl
  import DomexWeb.Components.AcControl
  import DomexWeb.Components.GenericSwitch

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe_all()
      PubSub.subscribe_discovery()
    end

    devices = Domex.list_devices()
    devices_map = Map.new(devices, fn d -> {d.id, d} end)

    socket =
      socket
      |> assign(:page_title, "Smart Home Dashboard")
      |> assign(:devices, devices_map)
      |> assign(:discovered, %{})
      |> assign(:show_add_modal, false)
      |> assign(
        :new_device_form,
        to_form(%{
          "name" => "",
          "type" => "light",
          "adapter" => "Domex.Adapter.YeelightLan",
          "host" => "",
          "port" => "55443",
          "token" => ""
        })
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:device_updated, %Shadow{} = shadow}, socket) do
    new_devices = Map.put(socket.assigns.devices, shadow.id, shadow)
    {:noreply, assign(socket, :devices, new_devices)}
  end

  def handle_info({:device_discovered, meta}, socket) do
    id = to_string(meta[:id] || meta["id"])
    # If device is not already configured, show in discovered list
    if Map.has_key?(socket.assigns.devices, id) do
      {:noreply, socket}
    else
      new_disc = Map.put(socket.assigns.discovered, id, meta)
      {:noreply, assign(socket, :discovered, new_disc)}
    end
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.devices, id) do
      {:ok, device} ->
        new_power = !device.power
        # Optimistic update
        updated_device = %{device | power: new_power}
        new_devices = Map.put(socket.assigns.devices, id, updated_device)

        Task.start(fn -> Domex.set_power(id, new_power) end)

        {:noreply, assign(socket, :devices, new_devices)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_brightness", params, socket) do
    id = params["device_id"] || params["id"]
    val_str = params["brightness"]

    case Integer.parse(val_str || "") do
      {val, _} ->
        case Map.fetch(socket.assigns.devices, id) do
          {:ok, device} ->
            updated = %{device | brightness: val, power: true}
            new_devices = Map.put(socket.assigns.devices, id, updated)

            Task.start(fn -> Domex.set_brightness(id, val) end)

            {:noreply, assign(socket, :devices, new_devices)}

          :error ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_color_temp", params, socket) do
    id = params["device_id"] || params["id"]
    val_str = params["color_temp"]

    case Integer.parse(val_str || "") do
      {val, _} ->
        case Map.fetch(socket.assigns.devices, id) do
          {:ok, device} ->
            updated = %{device | color_temp: val, power: true}
            new_devices = Map.put(socket.assigns.devices, id, updated)

            Task.start(fn -> Domex.set_color_temp(id, val) end)

            {:noreply, assign(socket, :devices, new_devices)}

          :error ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_rgb", params, socket) do
    id = params["device_id"] || params["id"]
    hex_str = params["rgb"] || "#ffffff"
    clean_hex = String.trim_leading(hex_str, "#")

    case Integer.parse(clean_hex, 16) do
      {val, _} ->
        case Map.fetch(socket.assigns.devices, id) do
          {:ok, device} ->
            updated = %{device | rgb: val, power: true}
            new_devices = Map.put(socket.assigns.devices, id, updated)

            Task.start(fn -> Domex.set_rgb(id, val) end)

            {:noreply, assign(socket, :devices, new_devices)}

          :error ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("change_temp", %{"id" => id, "delta" => delta_str}, socket) do
    delta = String.to_float(delta_str <> ".0")

    case Map.fetch(socket.assigns.devices, id) do
      {:ok, device} ->
        curr = device.ac_target_temp || 24.0
        new_temp = max(16.0, min(30.0, curr + delta))
        updated = %{device | ac_target_temp: new_temp, power: true}
        new_devices = Map.put(socket.assigns.devices, id, updated)

        Task.start(fn -> Domex.set_ac(id, %{target_temp: new_temp, power: true}) end)

        {:noreply, assign(socket, :devices, new_devices)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_mode", %{"id" => id, "mode" => mode_str}, socket) do
    mode = String.to_existing_atom(mode_str)

    case Map.fetch(socket.assigns.devices, id) do
      {:ok, device} ->
        updated = %{device | ac_mode: mode, power: true}
        new_devices = Map.put(socket.assigns.devices, id, updated)

        Task.start(fn -> Domex.set_ac(id, %{mode: mode, power: true}) end)

        {:noreply, assign(socket, :devices, new_devices)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_fan_speed", %{"id" => id, "speed" => speed_str}, socket) do
    speed = String.to_existing_atom(speed_str)

    case Map.fetch(socket.assigns.devices, id) do
      {:ok, device} ->
        updated = %{device | ac_fan_speed: speed}
        new_devices = Map.put(socket.assigns.devices, id, updated)

        Task.start(fn -> Domex.set_ac(id, %{fan_speed: speed}) end)

        {:noreply, assign(socket, :devices, new_devices)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_swing", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.devices, id) do
      {:ok, device} ->
        new_swing = !device.ac_swing_vertical
        updated = %{device | ac_swing_vertical: new_swing}
        new_devices = Map.put(socket.assigns.devices, id, updated)

        Task.start(fn -> Domex.set_ac(id, %{swing_vertical: new_swing}) end)

        {:noreply, assign(socket, :devices, new_devices)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("trigger_discovery", _, socket) do
    Domex.discover()
    {:noreply, put_flash(socket, :info, "Discovery sweep broadcasted to local network")}
  end

  def handle_event("add_discovered", %{"id" => id}, socket) do
    case Map.pop(socket.assigns.discovered, id) do
      {nil, _} ->
        {:noreply, socket}

      {meta, remaining} ->
        case Domex.add_device(meta) do
          {:ok, shadow} ->
            new_devices = Map.put(socket.assigns.devices, shadow.id, shadow)

            socket =
              socket
              |> assign(:devices, new_devices)
              |> assign(:discovered, remaining)
              |> put_flash(:info, "Device '#{shadow.name}' added successfully")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to add device: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("open_add_modal", _, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  def handle_event("close_add_modal", _, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  def handle_event("save_device", %{"device" => params}, socket) do
    id =
      case params["id"] do
        s when is_binary(s) and s != "" -> s
        _ -> "dev_#{:erlang.unique_integer([:positive])}"
      end

    port =
      case Integer.parse(params["port"] || "") do
        {p, _} -> p
        :error -> nil
      end

    config = %{
      id: id,
      name: params["name"] || id,
      type: String.to_existing_atom(params["type"] || "switch"),
      adapter: params["adapter"],
      host: params["host"],
      port: port,
      token: params["token"]
    }

    case Domex.add_device(config) do
      {:ok, shadow} ->
        new_devices = Map.put(socket.assigns.devices, shadow.id, shadow)

        socket =
          socket
          |> assign(:devices, new_devices)
          |> assign(:show_add_modal, false)
          |> put_flash(:info, "Device '#{shadow.name}' created")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error creating device: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_device", %{"id" => id}, socket) do
    Domex.remove_device(id)
    new_devices = Map.delete(socket.assigns.devices, id)
    {:noreply, assign(socket, :devices, new_devices) |> put_flash(:info, "Device removed")}
  end
end

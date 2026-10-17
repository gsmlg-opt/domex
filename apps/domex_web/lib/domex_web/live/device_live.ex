defmodule DomexWeb.DeviceLive do
  @moduledoc """
  Detailed control and diagnostics view for a single smart device.
  """

  use DomexWeb, :live_view

  alias Domex.Device.Shadow
  alias Domex.PubSub
  import DomexWeb.Components.LightControl
  import DomexWeb.Components.AcControl
  import DomexWeb.Components.GenericSwitch

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe_device(id)
    end

    case Domex.get_device(id) do
      {:ok, shadow} ->
        socket =
          socket
          |> assign(:page_title, shadow.name)
          |> assign(:device_id, id)
          |> assign(:shadow, shadow)

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Device '#{id}' not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:device_updated, %Shadow{id: id} = shadow}, socket) do
    if socket.assigns.device_id == id do
      {:noreply, assign(socket, :shadow, shadow)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    new_power = !socket.assigns.shadow.power
    updated = %{socket.assigns.shadow | power: new_power}

    Task.start(fn -> Domex.set_power(id, new_power) end)

    {:noreply, assign(socket, :shadow, updated)}
  end

  def handle_event("set_brightness", params, socket) do
    id = params["device_id"] || params["id"] || socket.assigns.device_id
    val_str = params["brightness"]

    case Integer.parse(val_str || "") do
      {val, _} ->
        updated = %{socket.assigns.shadow | brightness: val, power: true}
        Task.start(fn -> Domex.set_brightness(id, val) end)
        {:noreply, assign(socket, :shadow, updated)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_color_temp", params, socket) do
    id = params["device_id"] || params["id"] || socket.assigns.device_id
    val_str = params["color_temp"]

    case Integer.parse(val_str || "") do
      {val, _} ->
        updated = %{socket.assigns.shadow | color_temp: val, power: true}
        Task.start(fn -> Domex.set_color_temp(id, val) end)
        {:noreply, assign(socket, :shadow, updated)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_rgb", params, socket) do
    id = params["device_id"] || params["id"] || socket.assigns.device_id
    hex_str = params["rgb"] || "#ffffff"
    clean_hex = String.trim_leading(hex_str, "#")

    case Integer.parse(clean_hex, 16) do
      {val, _} ->
        updated = %{socket.assigns.shadow | rgb: val, power: true}
        Task.start(fn -> Domex.set_rgb(id, val) end)
        {:noreply, assign(socket, :shadow, updated)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("change_temp", %{"id" => id, "delta" => delta_str}, socket) do
    delta = String.to_float(delta_str <> ".0")
    curr = socket.assigns.shadow.ac_target_temp || 24.0
    new_temp = max(16.0, min(30.0, curr + delta))
    updated = %{socket.assigns.shadow | ac_target_temp: new_temp, power: true}

    Task.start(fn -> Domex.set_ac(id, %{target_temp: new_temp, power: true}) end)

    {:noreply, assign(socket, :shadow, updated)}
  end

  def handle_event("set_mode", %{"id" => id, "mode" => mode_str}, socket) do
    mode = String.to_existing_atom(mode_str)
    updated = %{socket.assigns.shadow | ac_mode: mode, power: true}

    Task.start(fn -> Domex.set_ac(id, %{mode: mode, power: true}) end)

    {:noreply, assign(socket, :shadow, updated)}
  end

  def handle_event("set_fan_speed", %{"id" => id, "speed" => speed_str}, socket) do
    speed = String.to_existing_atom(speed_str)
    updated = %{socket.assigns.shadow | ac_fan_speed: speed}

    Task.start(fn -> Domex.set_ac(id, %{fan_speed: speed}) end)

    {:noreply, assign(socket, :shadow, updated)}
  end

  def handle_event("toggle_swing", %{"id" => id}, socket) do
    new_swing = !socket.assigns.shadow.ac_swing_vertical
    updated = %{socket.assigns.shadow | ac_swing_vertical: new_swing}

    Task.start(fn -> Domex.set_ac(id, %{swing_vertical: new_swing}) end)

    {:noreply, assign(socket, :shadow, updated)}
  end

  def handle_event("delete_device", %{"id" => id}, socket) do
    Domex.remove_device(id)

    {:noreply,
     socket
     |> put_flash(:info, "Device '#{socket.assigns.shadow.name}' removed")
     |> push_navigate(to: ~p"/")}
  end
end

defmodule Domex.PubSub do
  @moduledoc """
  Defines scoped Phoenix.PubSub topics and broadcasting helpers for Domex.
  """

  @pubsub_server Domex.PubSub

  @topic_all "devices:all"
  @topic_discovery "discovery:devices"

  @doc "Topic for all device shadow updates"
  def topic_all, do: @topic_all

  @doc "Topic for a specific device shadow update"
  def topic_device(device_id), do: "device:#{device_id}"

  @doc "Topic for newly discovered devices on the network"
  def topic_discovery, do: @topic_discovery

  @doc "Subscribes the calling process to all device events"
  def subscribe_all do
    Phoenix.PubSub.subscribe(@pubsub_server, @topic_all)
  end

  @doc "Subscribes the calling process to a specific device's events"
  def subscribe_device(device_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, topic_device(device_id))
  end

  @doc "Subscribes the calling process to network discovery events"
  def subscribe_discovery do
    Phoenix.PubSub.subscribe(@pubsub_server, @topic_discovery)
  end

  @doc "Broadcasts a shadow state change to both the specific device topic and the global topic"
  def broadcast_shadow(%Domex.Device.Shadow{} = shadow) do
    Phoenix.PubSub.broadcast(@pubsub_server, @topic_all, {:device_updated, shadow})
    Phoenix.PubSub.broadcast(@pubsub_server, topic_device(shadow.id), {:device_updated, shadow})
    :ok
  end

  @doc "Broadcasts a newly discovered device metadata"
  def broadcast_discovery(device_meta) when is_map(device_meta) do
    Phoenix.PubSub.broadcast(@pubsub_server, @topic_discovery, {:device_discovered, device_meta})
  end
end

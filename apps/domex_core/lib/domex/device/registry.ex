defmodule Domex.Device.Registry do
  @moduledoc """
  Elixir Registry for naming dynamic device session processes.
  """

  def via_tuple(device_id) when is_binary(device_id) or is_atom(device_id) do
    {:via, Registry, {__MODULE__, to_string(device_id)}}
  end

  def whereis(device_id) do
    case Registry.lookup(__MODULE__, to_string(device_id)) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end
end

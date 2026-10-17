defmodule Domex.Protocol.MiioSpec do
  @moduledoc """
  Sans-I/O mapping and payload builder for Xiaomi MIoT Specification (SIID/PIID).

  MIoT divides device capabilities into Services (SIID), Properties (PIID),
  and Actions (AIID).
  """

  @type siid :: pos_integer()
  @type piid :: pos_integer()
  @type did :: integer() | String.t()

  # Common MIoT Profiles
  @plug_switch_profile %{
    power: {2, 1}
  }

  @light_profile %{
    power: {2, 1},
    brightness: {2, 2},
    color_temp: {2, 3},
    color: {2, 4}
  }

  @doc """
  Builds the payload map for a `get_properties` call.
  `specs` can be a list of `{siid, piid}` tuples.
  """
  @spec get_properties(pos_integer(), did(), list({siid(), piid()})) :: map()
  def get_properties(id, did, specs) when is_integer(id) and is_list(specs) do
    params =
      Enum.map(specs, fn {siid, piid} ->
        %{
          did: to_string(did),
          siid: siid,
          piid: piid
        }
      end)

    %{
      id: id,
      method: "get_properties",
      params: params
    }
  end

  @doc """
  Builds the payload map for a `set_properties` call for a single property.
  """
  @spec set_property(pos_integer(), did(), siid(), piid(), term()) :: map()
  def set_property(id, did, siid, piid, value) when is_integer(id) do
    %{
      id: id,
      method: "set_properties",
      params: [
        %{
          did: to_string(did),
          siid: siid,
          piid: piid,
          value: value
        }
      ]
    }
  end

  @doc """
  Builds the payload map for multiple `set_properties`.
  `items` is a list of `{siid, piid, value}` tuples.
  """
  @spec set_properties(pos_integer(), did(), list({siid(), piid(), term()})) :: map()
  def set_properties(id, did, items) when is_integer(id) and is_list(items) do
    params =
      Enum.map(items, fn {siid, piid, value} ->
        %{
          did: to_string(did),
          siid: siid,
          piid: piid,
          value: value
        }
      end)

    %{
      id: id,
      method: "set_properties",
      params: params
    }
  end

  @doc """
  Decodes a MIoT `get_properties` result list into a map of `{siid, piid} => value`.
  Filters out items where `code != 0`.
  """
  @spec decode_properties(list(map())) :: %{{siid(), piid()} => term()}
  def decode_properties(result) when is_list(result) do
    Enum.reduce(result, %{}, fn item, acc ->
      case item do
        %{"siid" => siid, "piid" => piid, "code" => 0, "value" => val} ->
          Map.put(acc, {siid, piid}, val)

        %{siid: siid, piid: piid, code: 0, value: val} ->
          Map.put(acc, {siid, piid}, val)

        _ ->
          acc
      end
    end)
  end

  @doc """
  Decodes a MIoT result into a named map given a mapping schema of `%{name => {siid, piid}}`.
  """
  @spec map_named_properties(list(map()), %{atom() => {siid(), piid()}}) :: %{atom() => term()}
  def map_named_properties(result, schema) when is_list(result) and is_map(schema) do
    raw_props = decode_properties(result)

    Enum.reduce(schema, %{}, fn {name, {siid, piid}}, acc ->
      case Map.fetch(raw_props, {siid, piid}) do
        {:ok, val} -> Map.put(acc, name, val)
        :error -> acc
      end
    end)
  end

  def plug_profile, do: @plug_switch_profile
  def light_profile, do: @light_profile
end

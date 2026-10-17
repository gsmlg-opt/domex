defmodule Domex.Protocol.MiioTest do
  use ExUnit.Case, async: true
  alias Domex.Protocol.Miio
  alias Domex.Protocol.MiioSpec

  @token_hex "0123456789abcdef0123456789abcdef"
  @token_bin Base.decode16!(@token_hex, case: :lower)
  @did 123_456_789
  @stamp 1_600_000_000

  describe "hello/0 and decode_hello/1" do
    test "generates standard 32-byte hello packet" do
      hello = Miio.hello()
      assert byte_size(hello) == 32
      assert <<0x2131::16, 32::16, _::binary>> = hello
    end

    test "decodes hello response packet" do
      response = <<0x2131::16, 32::16, 0::32, @did::32, @stamp::32, 0xFF::128>>
      assert {:ok, %{did: @did, stamp: @stamp, unknown: 0}} = Miio.decode_hello(response)
    end

    test "rejects non-hello packet" do
      invalid = <<0x1234::16, 32::16, 0::224>>
      assert {:error, :not_hello_packet} = Miio.decode_hello(invalid)
    end
  end

  describe "derive_keys/1" do
    test "derives consistent 16-byte Key and IV from hex and binary tokens" do
      {key1, iv1} = Miio.derive_keys(@token_hex)
      {key2, iv2} = Miio.derive_keys(@token_bin)

      assert byte_size(key1) == 16
      assert byte_size(iv1) == 16
      assert key1 == key2
      assert iv1 == iv2
    end
  end

  describe "encode_packet/5 and decode_packet/2" do
    test "roundtrips payload encryption and decryption with hex token" do
      payload = %{"id" => 1, "method" => "get_prop", "params" => ["power"]}

      encoded = Miio.encode_packet(@did, @stamp, @token_hex, payload)

      assert byte_size(encoded) > 32

      assert <<0x2131::16, total_len::16, 0::32, @did::32, @stamp::32, _checksum::16-bytes,
               _ciphertext::binary>> =
               encoded

      assert byte_size(encoded) == total_len

      assert {:ok, decoded} = Miio.decode_packet(encoded, @token_hex)
      assert decoded.did == @did
      assert decoded.stamp == @stamp
      assert decoded.payload == payload
    end

    test "roundtrips with binary token" do
      payload = %{"id" => 2, "result" => ["on"]}
      encoded = Miio.encode_packet(@did, @stamp, @token_bin, payload)

      assert {:ok, decoded} = Miio.decode_packet(encoded, @token_bin)
      assert decoded.payload == payload
    end

    test "rejects packet with invalid checksum" do
      payload = %{"id" => 1, "method" => "get_prop"}
      encoded = Miio.encode_packet(@did, @stamp, @token_hex, payload)

      # Corrupt checksum at byte 16
      <<head::binary-size(16), _ck::binary-size(16), tail::binary>> = encoded
      corrupted = head <> :crypto.strong_rand_bytes(16) <> tail

      assert {:error, :invalid_checksum} = Miio.decode_packet(corrupted, @token_hex)
    end

    test "rejects packet with wrong token (checksum mismatch)" do
      payload = %{"id" => 1, "method" => "get_prop"}
      encoded = Miio.encode_packet(@did, @stamp, @token_hex, payload)
      wrong_token = "ffffffffffffffffffffffffffffffff"

      assert {:error, :invalid_checksum} = Miio.decode_packet(encoded, wrong_token)
    end

    test "rejects malformed packet" do
      assert {:error, :malformed_packet} = Miio.decode_packet(<<1, 2, 3>>, @token_hex)
    end
  end

  describe "Domex.Protocol.MiioSpec" do
    test "builds get_properties payload" do
      req = MiioSpec.get_properties(10, @did, [{2, 1}, {2, 2}])

      assert req.id == 10
      assert req.method == "get_properties"

      assert req.params == [
               %{did: to_string(@did), siid: 2, piid: 1},
               %{did: to_string(@did), siid: 2, piid: 2}
             ]
    end

    test "builds set_property payload" do
      req = MiioSpec.set_property(11, @did, 2, 1, true)

      assert req.id == 11
      assert req.method == "set_properties"
      assert req.params == [%{did: to_string(@did), siid: 2, piid: 1, value: true}]
    end

    test "decodes properties results and maps named properties" do
      results = [
        %{"did" => to_string(@did), "siid" => 2, "piid" => 1, "code" => 0, "value" => true},
        %{"did" => to_string(@did), "siid" => 2, "piid" => 2, "code" => 0, "value" => 80},
        %{"did" => to_string(@did), "siid" => 2, "piid" => 3, "code" => -1}
      ]

      props = MiioSpec.decode_properties(results)
      assert props[{2, 1}] == true
      assert props[{2, 2}] == 80
      refute Map.has_key?(props, {2, 3})

      named = MiioSpec.map_named_properties(results, MiioSpec.light_profile())
      assert named.power == true
      assert named.brightness == 80
      refute Map.has_key?(named, :color_temp)
    end
  end
end

defmodule Domex.Protocol.YeelightTest do
  use ExUnit.Case, async: true
  alias Domex.Protocol.Yeelight

  describe "encode_call/3" do
    test "encodes command to JSON-RPC ending with CRLF" do
      encoded = Yeelight.encode_call(1, "set_power", ["on", "smooth", 500])
      assert String.ends_with?(encoded, "\r\n")

      assert {:ok, %{"id" => 1, "method" => "set_power", "params" => ["on", "smooth", 500]}} =
               Jason.decode(String.trim_trailing(encoded, "\r\n"))
    end

    test "encodes command with empty params by default" do
      encoded = Yeelight.encode_call(42, "get_prop")

      assert {:ok, %{"id" => 42, "method" => "get_prop", "params" => []}} =
               Jason.decode(String.trim_trailing(encoded, "\r\n"))
    end
  end

  describe "decode_frames/1" do
    test "decodes single complete response frame" do
      data = ~s({"id":1,"result":["ok"]}\r\n)
      assert {:ok, [{:response, 1, ["ok"]}], ""} = Yeelight.decode_frames(data)
    end

    test "decodes notification / props frame" do
      data = ~s({"method":"props","params":{"power":"on","bright":80}}\r\n)

      assert {:ok, [{:props, %{"power" => "on", "bright" => 80}}], ""} =
               Yeelight.decode_frames(data)
    end

    test "decodes error response frame" do
      data = ~s({"id":2,"error":{"code":-1,"message":"client quota exceeded"}}\r\n)

      assert {:ok, [{:error_response, 2, %{"code" => -1, "message" => "client quota exceeded"}}],
              ""} =
               Yeelight.decode_frames(data)
    end

    test "handles multiple frames in a single buffer" do
      data = ~s({"id":1,"result":["ok"]}\r\n{"method":"props","params":{"bright":100}}\r\n)

      assert {:ok,
              [
                {:response, 1, ["ok"]},
                {:props, %{"bright" => 100}}
              ], ""} = Yeelight.decode_frames(data)
    end

    test "handles incomplete frame and preserves remaining buffer" do
      data = ~s({"id":1,"result":["ok"]}\r\n{"id":2,"resu)
      assert {:ok, [{:response, 1, ["ok"]}], ~s({"id":2,"resu)} = Yeelight.decode_frames(data)
    end

    test "discards malformed lines cleanly without crashing" do
      data = "NOT JSON GARBAGE\r\n{\"id\":3,\"result\":[\"ok\"]}\r\n"
      assert {:ok, [{:response, 3, ["ok"]}], ""} = Yeelight.decode_frames(data)
    end
  end

  describe "parse_advertisement/1" do
    test "parses full SSDP advertisement correctly" do
      packet = """
      HTTP/1.1 200 OK\r
      Location: yeelight://192.168.1.105:55443\r
      id: 0x00000000032f8abc\r
      model: color\r
      power: on\r
      bright: 75\r
      color_mode: 1\r
      ct: 4000\r
      rgb: 16711680\r
      hue: 359\r
      sat: 100\r
      name: Bedside Lamp\r
      support: get_prop set_default set_power toggle set_bright start_cf stop_cf set_scene cron_add cron_get cron_del set_ct_abx set_rgb\r
      \r
      """

      assert {:ok, ad} = Yeelight.parse_advertisement(packet)
      assert ad.id == "0x00000000032f8abc"
      assert ad.location == "yeelight://192.168.1.105:55443"
      assert ad.host == "192.168.1.105"
      assert ad.port == 55443
      assert ad.model == "color"
      assert ad.power == "on"
      assert ad.bright == 75
      assert ad.color_mode == 1
      assert ad.ct == 4000
      assert ad.rgb == 16_711_680
      assert ad.name == "Bedside Lamp"
      assert "set_power" in ad.support
    end

    test "returns error for non-yeelight packet" do
      packet = "HTTP/1.1 200 OK\r\nServer: Custom\r\n\r\n"
      assert {:error, :not_yeelight} = Yeelight.parse_advertisement(packet)
    end
  end
end

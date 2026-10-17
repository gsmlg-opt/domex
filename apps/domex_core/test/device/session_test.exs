defmodule Domex.Device.SessionTest do
  use ExUnit.Case, async: false

  alias Domex.Device.DynamicSupervisor, as: DevSupervisor
  alias Domex.Device.Session
  alias Domex.Device.Shadow
  alias Domex.PubSub

  setup do
    # Start a mock TCP server to simulate a Yeelight device
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    {:ok, listen_socket: listen_socket, port: port}
  end

  test "starts device session and handles connection, props, and PubSub", %{
    listen_socket: listen_socket,
    port: port
  } do
    PubSub.subscribe_all()

    device_id = "test_yeelight_#{:erlang.unique_integer([:positive])}"

    config = %{
      id: device_id,
      adapter: Domex.Adapter.YeelightLan,
      host: "127.0.0.1",
      port: port,
      name: "Mock Yeelight"
    }

    # Start session under dynamic supervisor
    assert {:ok, pid} = DevSupervisor.start_device(config)
    assert is_pid(pid)

    # Accept connection on mock server
    {:ok, client_socket} = :gen_tcp.accept(listen_socket, 1_000)

    # Device session sends initial get_prop on connection
    {:ok, initial_data} = :gen_tcp.recv(client_socket, 0, 1_000)
    assert initial_data =~ "get_prop"

    # PubSub broadcast that device is online
    assert_receive {:device_updated, %Shadow{id: ^device_id, online?: true}}, 1_000

    # Simulate device reporting property notification
    props_msg = ~s({"method":"props","params":{"power":"on","bright":77}}\r\n)
    :ok = :gen_tcp.send(client_socket, props_msg)

    # PubSub receives updated shadow
    assert_receive {:device_updated, %Shadow{id: ^device_id, power: true, brightness: 77}}, 1_000

    # Verify get_shadow/1
    shadow = Session.get_shadow(device_id)
    assert shadow.power == true
    assert shadow.brightness == 77
    assert shadow.online? == true

    # Clean up
    :gen_tcp.close(client_socket)
    :gen_tcp.close(listen_socket)
    DevSupervisor.stop_device(device_id)
  end

  test "executes RPC command with response correlation", %{
    listen_socket: listen_socket,
    port: port
  } do
    device_id = "test_rpc_#{:erlang.unique_integer([:positive])}"

    config = %{
      id: device_id,
      adapter: Domex.Adapter.YeelightLan,
      host: "127.0.0.1",
      port: port
    }

    assert {:ok, _pid} = DevSupervisor.start_device(config)
    {:ok, client_socket} = :gen_tcp.accept(listen_socket, 1_000)
    {:ok, _initial} = :gen_tcp.recv(client_socket, 0, 1_000)

    # In a separate task, send command
    task =
      Task.async(fn ->
        Session.command(device_id, :set_power, [true], 2_000)
      end)

    # Mock server receives command
    {:ok, cmd_data} = :gen_tcp.recv(client_socket, 0, 1_000)
    assert {:ok, %{"id" => req_id, "method" => "set_power"}} = Jason.decode(String.trim(cmd_data))

    # Mock server responds with result
    resp = ~s({"id":#{req_id},"result":["ok"]}\r\n)
    :ok = :gen_tcp.send(client_socket, resp)

    assert Task.await(task) == {:ok, ["ok"]}

    :gen_tcp.close(client_socket)
    :gen_tcp.close(listen_socket)
    DevSupervisor.stop_device(device_id)
  end

  test "fault tolerance: TCP disconnection enters backoff and does not crash supervisor", %{
    listen_socket: listen_socket,
    port: port
  } do
    device_id = "test_fault_#{:erlang.unique_integer([:positive])}"

    config = %{
      id: device_id,
      adapter: Domex.Adapter.YeelightLan,
      host: "127.0.0.1",
      port: port
    }

    assert {:ok, pid} = DevSupervisor.start_device(config)
    {:ok, client_socket} = :gen_tcp.accept(listen_socket, 1_000)
    {:ok, _initial} = :gen_tcp.recv(client_socket, 0, 1_000)

    # Abruptly kill/close the client connection
    :gen_tcp.close(client_socket)

    # Wait a moment for tcp_closed message to be handled
    Process.sleep(50)

    # Session process should STILL be alive!
    assert Process.alive?(pid)

    shadow = Session.get_shadow(device_id)
    assert shadow.online? == false

    # DynamicSupervisor still has child
    assert Process.alive?(Process.whereis(Domex.Device.DynamicSupervisor))

    :gen_tcp.close(listen_socket)
    DevSupervisor.stop_device(device_id)
  end
end

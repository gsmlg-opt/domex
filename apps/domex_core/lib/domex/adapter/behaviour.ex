defmodule Domex.Adapter.Behaviour do
  @moduledoc """
  Defines the behaviour required for Domex device protocol adapters.

  Adapters are Sans-I/O or minimal stateful protocol handlers that:
  - Specify network transport (`:tcp` or `:udp`) and connection options
  - Generate initial handshake or probe packets on connection
  - Parse incoming network data into Shadow events and RPC replies
  - Encode domain commands into network binaries with request correlation IDs
  - Provide optional periodic poll packets
  """

  @type state :: term()
  @type req_id :: pos_integer() | binary()
  @type shadow_event :: {:props, map()} | {:state, map()} | {:online, boolean()}
  @type rpc_reply :: {req_id(), {:ok, term()} | {:error, term()}}

  @callback init(config :: map()) :: {:ok, state()} | {:error, term()}
  @callback transport() :: :tcp | :udp
  @callback default_port() :: :inet.port_number()
  @callback connect_opts(state()) ::
              {:ok, :inet.socket_address() | charlist() | String.t(), :inet.port_number(), list()}
  @callback handle_connected(state()) :: {:ok, list(binary()), state()}
  @callback handle_data(binary(), state()) ::
              {:ok, list(shadow_event()), list(rpc_reply()), state()}
  @callback encode_command(atom() | String.t(), term(), state()) ::
              {:ok, binary(), req_id(), state()} | {:error, term()}
  @callback poll(state()) :: {:ok, list(binary()), state()} | :noop

  defmacro __using__(_opts) do
    quote do
      @behaviour Domex.Adapter.Behaviour

      @impl true
      def poll(_state), do: :noop

      defoverridable poll: 1
    end
  end
end

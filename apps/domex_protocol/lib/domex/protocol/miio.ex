defmodule Domex.Protocol.Miio do
  @moduledoc """
  Sans-I/O codec for the Xiaomi miIO (Mi Home) binary UDP protocol.

  Specifications:
  - 32-byte header:
    `<<0x2131::16, length::16, unknown::32, did::32, stamp::32, checksum::binary-size(16), encrypted::binary>>`
  - Token is 16 bytes (or 32-char hex string).
  - Key derivation:
    - Key = MD5(token)
    - IV = MD5(Key <> token)
  - AES-128-CBC encryption with PKCS#7 padding.
  - MD5 checksum validation: MD5(header_16_bytes <> token <> ciphertext).
  """

  @magic 0x2131
  @header_len 32

  @doc """
  Builds a 32-byte miIO Hello probe packet.
  Used for device discovery and initial stamp synchronization.
  """
  @spec hello() :: binary()
  def hello do
    <<@magic::16, 32::16, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  end

  @doc """
  Checks if binary is a 32-byte Hello probe or Hello response.
  Returns `{:ok, %{did: did, stamp: stamp, unknown: unknown, token_or_checksum: checksum}}`
  or `{:error, reason}`.
  """
  @spec decode_hello(binary()) :: {:ok, map()} | {:error, term()}
  def decode_hello(
        <<@magic::16, 32::16, unknown::32, did::32, stamp::32, checksum::binary-size(16)>>
      ) do
    {:ok,
     %{
       did: did,
       stamp: stamp,
       unknown: unknown,
       token_or_checksum: checksum
     }}
  end

  def decode_hello(_), do: {:error, :not_hello_packet}

  @doc """
  Derives the 16-byte AES Key and 16-byte IV from the device token.
  Token can be a 16-byte binary or a 32-character hex string.
  """
  @spec derive_keys(binary()) :: {binary(), binary()}
  def derive_keys(token) when is_binary(token) do
    raw_token = normalize_token(token)
    key = :crypto.hash(:md5, raw_token)
    iv = :crypto.hash(:md5, [key, raw_token])
    {key, iv}
  end

  @doc """
  Encodes an RPC call into a complete encrypted miIO binary packet.

  - `did`: Device ID (integer)
  - `stamp`: Device stamp (integer)
  - `token`: 16-byte token or 32-character hex string
  - `payload`: map to be JSON encoded (or already encoded JSON binary)
  - `unknown`: 32-bit unknown integer (defaults to 0)
  """
  @spec encode_packet(
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          map() | binary(),
          non_neg_integer()
        ) :: binary()
  def encode_packet(did, stamp, token, payload, unknown \\ 0)
      when is_integer(did) and is_integer(stamp) and is_binary(token) do
    raw_token = normalize_token(token)
    {key, iv} = derive_keys(raw_token)

    plaintext =
      if is_binary(payload) do
        payload
      else
        Jason.encode_to_iodata!(payload) |> IO.iodata_to_binary()
      end

    padded = pkcs7_pad(plaintext)
    ciphertext = :crypto.crypto_one_time(:aes_128_cbc, key, iv, padded, true)

    total_len = @header_len + byte_size(ciphertext)
    first_16 = <<@magic::16, total_len::16, unknown::32, did::32, stamp::32>>
    checksum = :crypto.hash(:md5, [first_16, raw_token, ciphertext])

    <<first_16::binary, checksum::binary-size(16), ciphertext::binary>>
  end

  @doc """
  Decodes and verifies an encrypted miIO binary packet.

  Returns `{:ok, %{did: did, stamp: stamp, unknown: unknown, payload: map()}}`
  or `{:error, reason}`.
  """
  @spec decode_packet(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def decode_packet(data, token) when is_binary(data) and is_binary(token) do
    case data do
      <<@magic::16, total_len::16, unknown::32, did::32, stamp::32, checksum::binary-size(16),
        ciphertext::binary>> ->
        if byte_size(data) != total_len do
          {:error, :length_mismatch}
        else
          raw_token = normalize_token(token)
          first_16 = <<@magic::16, total_len::16, unknown::32, did::32, stamp::32>>
          expected_checksum = :crypto.hash(:md5, [first_16, raw_token, ciphertext])

          if checksum != expected_checksum do
            {:error, :invalid_checksum}
          else
            {key, iv} = derive_keys(raw_token)
            padded = :crypto.crypto_one_time(:aes_128_cbc, key, iv, ciphertext, false)

            case pkcs7_unpad(padded) do
              {:ok, plaintext} ->
                # Clean up any optional trailing null bytes
                cleaned = String.trim_trailing(plaintext, <<0>>)

                case Jason.decode(cleaned) do
                  {:ok, payload} ->
                    {:ok,
                     %{
                       did: did,
                       stamp: stamp,
                       unknown: unknown,
                       payload: payload
                     }}

                  {:error, err} ->
                    {:error, {:json_decode_error, err}}
                end

              {:error, reason} ->
                {:error, reason}
            end
          end
        end

      _ ->
        {:error, :malformed_packet}
    end
  end

  @doc """
  Normalizes a token: converts 32-character hex string into 16-byte binary,
  or passes 16-byte binary through as-is.
  """
  @spec normalize_token(binary()) :: binary()
  def normalize_token(token) when is_binary(token) do
    cond do
      byte_size(token) == 16 ->
        token

      byte_size(token) == 32 ->
        case Base.decode16(token, case: :mixed) do
          {:ok, binary} -> binary
          :error -> raise ArgumentError, "Invalid hex token string: #{token}"
        end

      true ->
        raise ArgumentError,
              "Token must be 16 bytes or 32 hex characters, got #{byte_size(token)} bytes"
    end
  end

  # PKCS#7 padding
  defp pkcs7_pad(data) do
    pad_len = 16 - rem(byte_size(data), 16)
    pad_len = if pad_len == 0, do: 16, else: pad_len
    data <> :binary.copy(<<pad_len>>, pad_len)
  end

  defp pkcs7_unpad(data) when byte_size(data) > 0 and rem(byte_size(data), 16) == 0 do
    pad_len = :binary.last(data)

    if pad_len > 0 and pad_len <= 16 do
      data_len = byte_size(data) - pad_len
      <<unpadded::binary-size(^data_len), padding::binary>> = data

      if padding == :binary.copy(<<pad_len>>, pad_len) do
        {:ok, unpadded}
      else
        {:error, :invalid_padding}
      end
    else
      {:error, :invalid_padding}
    end
  end

  defp pkcs7_unpad(_), do: {:error, :invalid_padding}
end

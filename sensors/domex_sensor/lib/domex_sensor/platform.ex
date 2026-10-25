defmodule DomexSensor.Platform do
  @moduledoc "Routes OS/architecture pairs to native probe sources and compiler targets."

  def resolve(os, architecture) do
    arch = architecture |> to_string() |> String.split("-") |> hd()

    case {os, arch} do
      {{:unix, :darwin}, arch} when arch in ["arm64", "aarch64"] ->
        {:ok, darwin("arm64", 0x0100000C)}

      {{:unix, :darwin}, arch} when arch in ["x86_64", "amd64"] ->
        {:ok, darwin("x86_64", 0x01000007)}

      {{:unix, :linux}, arch} ->
        {:ok, %{id: "linux-#{arch}", kind: :proc}}

      _ ->
        {:error,
         "Unsupported platform #{inspect(os)} / #{architecture}; supported: macOS arm64/x86_64 and Linux"}
    end
  end

  # Our compiler emits a thin 64-bit Mach-O. Never trust a copied executable's
  # filename or mtime: a binary built on another Mac can be newer than its source.
  def binary_matches?(path, platform) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 8)) do
      {:ok, <<0xCF, 0xFA, 0xED, 0xFE, cpu_type::little-32>>} -> cpu_type == platform.cpu_type
      _ -> false
    end
  end

  defp darwin(arch, cpu_type) do
    source = "darwin/#{arch}.c"

    %{
      id: "darwin-#{arch}",
      source: source,
      sources: [source, "system_probe.c"],
      cpu_type: cpu_type,
      compiler_args: ["-arch", arch, "-framework", "CoreFoundation", "-framework", "IOKit"]
    }
  end
end

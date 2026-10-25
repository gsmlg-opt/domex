defmodule DomexSensor.PlatformTest do
  use ExUnit.Case, async: true

  alias DomexSensor.Platform

  @moduletag :tmp_dir

  test "routes Apple Silicon architecture names to the arm64 macOS implementation" do
    for architecture <- ["arm64", "aarch64-apple-darwin25.0", ~c"aarch64-apple-darwin24.0"] do
      assert {:ok, platform} = Platform.resolve({:unix, :darwin}, architecture)
      assert platform.id == "darwin-arm64"
      assert platform.source == "darwin/arm64.c"
      assert platform.sources == ["darwin/arm64.c", "system_probe.c"]
      assert ["-arch", "arm64" | _] = platform.compiler_args
    end
  end

  test "routes Intel architecture names to a separate x86_64 macOS implementation" do
    for architecture <- ["x86_64", "amd64", ~c"x86_64-apple-darwin24.0"] do
      assert {:ok, platform} = Platform.resolve({:unix, :darwin}, architecture)
      assert platform.id == "darwin-x86_64"
      assert platform.source == "darwin/x86_64.c"
      assert ["-arch", "x86_64" | _] = platform.compiler_args
    end
  end

  test "rejects unsupported OS and architecture combinations explicitly" do
    for {os, arch} <- [
          {{:win32, :nt}, "amd64"},
          {{:unix, :darwin}, "riscv64"}
        ] do
      assert {:error, message} = Platform.resolve(os, arch)
      assert message =~ "Unsupported"
      assert message =~ arch
    end
  end

  test "Linux architectures use procfs without a native compiler" do
    for arch <- ["aarch64-linux-gnu", "x86_64-linux-gnu", "arm-linux-gnueabihf"] do
      assert {:ok, %{kind: :proc}} = Platform.resolve({:unix, :linux}, arch)
    end
  end

  test "recognizes the executable CPU type instead of trusting its name or timestamp", %{
    tmp_dir: directory
  } do
    path = Path.join(directory, "probe")
    {:ok, arm} = Platform.resolve({:unix, :darwin}, "arm64")
    {:ok, intel} = Platform.resolve({:unix, :darwin}, "x86_64")

    refute Platform.binary_matches?(path, arm)
    File.write!(path, <<0xCF, 0xFA, 0xED, 0xFE, 0x01000007::little-32>>)
    assert Platform.binary_matches?(path, intel)
    refute Platform.binary_matches?(path, arm)
    File.write!(path, <<0xCF, 0xFA, 0xED, 0xFE, 0x0100000C::little-32>>)
    assert Platform.binary_matches?(path, arm)
    refute Platform.binary_matches?(path, intel)
    File.write!(path, "not a native executable")
    refute Platform.binary_matches?(path, arm)
  end
end

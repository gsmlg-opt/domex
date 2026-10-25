defmodule DomexSensor.Probe do
  @moduledoc "Builds macOS probes during release assembly, so target devices need no compiler."
  alias DomexSensor.Platform

  def native_dir, do: Application.app_dir(:domex_sensor, "priv/native")

  def build! do
    case Platform.resolve(:os.type(), :erlang.system_info(:system_architecture)) do
      {:ok, %{kind: :proc}} ->
        :ok

      {:ok, target} ->
        state = %{
          platform: {:ok, target},
          opts: [],
          probe_path: Path.join([native_dir(), "bin", target.id, "system_probe"]),
          source_path: Path.join(native_dir(), target.source),
          sources: Enum.map(target.sources, &Path.join(native_dir(), &1))
        }

        case ensure(state) do
          :ok -> :ok
          {:error, message, _retry?} -> raise message
        end

      {:error, message} ->
        raise message
    end
  end

  def ensure(%{platform: {:error, message}}), do: {:error, message, false}

  def ensure(state) do
    cond do
      Keyword.get(state.opts, :skip_build, false) ->
        if File.regular?(state.probe_path),
          do: :ok,
          else: {:error, "Missing system probe: #{state.probe_path}", true}

      build_needed?(state) ->
        compile_probe(state)

      true ->
        :ok
    end
  end

  defp build_needed?(%{platform: {:ok, target}} = state) do
    if Platform.binary_matches?(state.probe_path, target) do
      {:ok, executable} = File.stat(state.probe_path, time: :posix)

      Enum.any?(state.sources, fn source ->
        case File.stat(source, time: :posix) do
          {:ok, source_stat} -> source_stat.mtime > executable.mtime
          {:error, _} -> false
        end
      end)
    else
      true
    end
  end

  defp compile_probe(state) do
    compiler = System.find_executable("cc")

    cond do
      not File.regular?(state.source_path) ->
        {:error, "Missing native source: #{state.source_path}", true}

      is_nil(compiler) ->
        {:error, "Building the macOS probe requires cc (Xcode Command Line Tools)", true}

      true ->
        {:ok, target} = state.platform
        temporary = state.probe_path <> ".#{System.unique_integer([:positive])}.tmp"
        File.mkdir_p!(Path.dirname(state.probe_path))

        args =
          ["-O2", "-Wall", "-Wextra", "-std=c11", state.source_path, "-o", temporary] ++
            target.compiler_args

        try do
          case System.cmd(compiler, args, stderr_to_stdout: true) do
            {_output, 0} ->
              if Platform.binary_matches?(temporary, target) do
                File.rename!(temporary, state.probe_path)
                :ok
              else
                {:error, "Compiled probe does not match #{target.id}", true}
              end

            {output, code} ->
              {:error, "Probe compilation failed (#{code}): #{String.slice(output, 0, 1_000)}",
               true}
          end
        after
          File.rm(temporary)
        end
    end
  rescue
    error in [ErlangError, File.Error] ->
      {:error, "Could not build probe: #{Exception.message(error)}", true}
  end
end

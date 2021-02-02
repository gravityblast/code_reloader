defmodule CodeReloader.Server do
  @moduledoc """
    Recompiles modified files in the current mix project by invoking configured reloadable compilers.

    Specify the compilers that should be run for reloading when starting the server, e.g.:

    ```
    children = [{CodeReloader.Server, [:elixir, :erlang]}]
    Supervisor.start_link(children, [strategy: :one_for_one])
    ```

    Code can then be reloaded by calling:
    
    ```
    CodeReloader.Server.reload!(mod)
    ```

    where `mod` will normally be a `Plug.Router` module containing the `CodeReloader.Plug`
    used to instigate a code reload on every web-server call (it could potentially 
    be any another module being used to kick-off the reload).

    The `mod` argument is used for two purposes:

    * To avoid race conditions from multiple calls: all code reloads from the same
      module are funneled through a sequential call operation.
    * To back-up the module's `.beam` file so if compilation of the module itself fails, 
      it can be restored to working order, otherwise code reload through that
      module would no-longer be available, which would kill an endpoint.

    We also keep track of the last time that we compiled the code, so that if the code changes
    outside of the VM, e.g. an external tool recompiles the code, we notice that the manifest
    is newer than when we compiled, and explicitly reload all modified modules (see `:code.modified_modules/0`)
    since compiling will potentially be a no-op.
    
    This code is based on that in the [Pheonix Project](https://github.com/phoenixframework/phoenix),
    without the Phoenix dependencies, and modified to deal with the edge-case of projects recompiled 
    outside of the `CodeReloader.Server` (the original only copes with modified source code).

  """
  use GenServer

  require Logger
  alias CodeReloader.Proxy

  def start_link(reloadable_compilers) do
    GenServer.start_link(__MODULE__, reloadable_compilers, name: __MODULE__)
  end

  def check_symlinks do
    GenServer.call(__MODULE__, :check_symlinks, :infinity)
  end

  def reload!(endpoint) do
    GenServer.call(__MODULE__, {:reload!, endpoint}, :infinity)
  end

  ## Callbacks

  def init(reloadable_compilers) do
    {:ok, {false, reloadable_compilers, System.os_time(:seconds)}}
  end

  def handle_call(:check_symlinks, _from, {checked?, reloadable_compilers, last_compile_time}) do
    if not checked? and Code.ensure_loaded?(Mix.Project) do
      build_path = Mix.Project.build_path()
      symlink = Path.join(Path.dirname(build_path), "#{__MODULE__}")

      case File.ln_s(build_path, symlink) do
        :ok ->
          File.rm(symlink)

        {:error, :eexist} ->
          File.rm(symlink)

        {:error, _} ->
          Logger.warn(
            "App is unable to create symlinks. CodeReloader will run " <>
              "considerably faster if symlinks are allowed." <> os_symlink(:os.type())
          )
      end
    end

    {:reply, :ok, {true, reloadable_compilers, last_compile_time}}
  end

  def handle_call({:reload!, endpoint}, from, {checked?, compilers, last_compile_time}) do
    backup = load_backup(endpoint)
    froms = all_waiting([from], endpoint)

    {res, out} =
      proxy_io(fn ->
        try do
          mix_compile(Code.ensure_loaded(Mix.Task), compilers, last_compile_time)
        catch
          :exit, {:shutdown, 1} ->
            :error

          kind, reason ->
            IO.puts(Exception.format(kind, reason, System.stacktrace()))
            :error
        end
      end)

    reply =
      case res do
        :ok ->
          {:ok, out}

        :error ->
          write_backup(backup)
          {:error, out}
      end

    Enum.each(froms, &GenServer.reply(&1, reply))
    {:noreply, {checked?, compilers, System.os_time(:seconds)}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp os_symlink({:win32, _}),
    do: " On Windows, such can be done by starting the shell with \"Run as Administrator\"."

  defp os_symlink(_), do: ""

  defp load_backup(mod) do
    mod
    |> :code.which()
    |> read_backup()
  end

  defp read_backup(path) when is_list(path) do
    case File.read(path) do
      {:ok, binary} -> {:ok, path, binary}
      _ -> :error
    end
  end

  defp read_backup(_path), do: :error

  defp write_backup({:ok, path, file}), do: File.write!(path, file)
  defp write_backup(:error), do: :ok

  defp all_waiting(acc, endpoint) do
    receive do
      {:"$gen_call", from, {:reload!, ^endpoint}} -> all_waiting([from | acc], endpoint)
    after
      0 -> acc
    end
  end

  # TODO: Remove the function_exported call after 1.3 support is removed
  # and just use loaded. apply/3 is used to prevent a compilation
  # warning.
  defp mix_compile({:module, Mix.Task}, compilers, last_compile_time) do
    if Mix.Project.umbrella?() do
      deps =
        if function_exported?(Mix.Dep.Umbrella, :cached, 0) do
          apply(Mix.Dep.Umbrella, :cached, [])
        else
          Mix.Dep.Umbrella.loaded()
        end

      Enum.each(deps, fn dep ->
        Mix.Dep.in_dependency(dep, fn _ ->
          mix_compile_unless_stale_config(compilers, last_compile_time)
        end)
      end)
    else
      mix_compile_unless_stale_config(compilers, last_compile_time)
      :ok
    end
  end

  defp mix_compile({:error, _reason}, _, _) do
    raise "the Code Reloader is enabled but Mix is not available. If you want to " <>
            "use the Code Reloader in production or inside an escript, you must add " <>
            ":mix to your applications list. Otherwise, you must disable code reloading " <>
            "in such environments"
  end

  defp mix_compile_unless_stale_config(compilers, last_compile_time) do
    manifests = Mix.Tasks.Compile.Elixir.manifests()
    configs = Mix.Project.config_files()

    # did the manifest change outside of us compiling the project?
    manifests_last_updated =
      Enum.map(manifests, &File.stat!(&1, time: :posix).mtime) |> Enum.max()

    out_of_date? = manifests_last_updated > last_compile_time

    case Mix.Utils.extract_stale(configs, manifests) do
      [] ->
        do_mix_compile(compilers, out_of_date?)

      files ->
        raise """
        could not compile application: #{Mix.Project.config()[:app]}.

        You must restart your server after changing the following config or lib files:

          * #{Enum.map_join(files, "\n  * ", &Path.relative_to_cwd/1)}
        """
    end
  end

  defp do_mix_compile(compilers, out_of_date?) do
    all = Mix.Project.config()[:compilers] || Mix.compilers()

    compilers =
      for compiler <- compilers, compiler in all do
        Mix.Task.reenable("compile.#{compiler}")
        compiler
      end

    # We call build_structure mostly for Windows so new
    # assets in priv are copied to the build directory.
    Mix.Project.build_structure()
    res = Enum.map(compilers, &Mix.Task.run("compile.#{&1}", []))

    if :ok in res && consolidate_protocols?() do
      Mix.Task.reenable("compile.protocols")
      Mix.Task.run("compile.protocols", [])
    end

    if(out_of_date?, do: reload_modules())

    res
  end

  defp consolidate_protocols? do
    Mix.Project.config()[:consolidate_protocols]
  end

  defp reload_modules() do
    :code.modified_modules()
    |> Enum.each(fn mod ->
      IO.puts("Reloading #{inspect(mod)}\n")

      case :code.soft_purge(mod) do
        true ->
          :code.load_file(mod)

        false ->
          Process.sleep(500)
          :code.purge(mod)
          :code.load_file(mod)
      end
    end)
  end

  defp proxy_io(fun) do
    original_gl = Process.group_leader()
    {:ok, proxy_gl} = Proxy.start()
    Process.group_leader(self(), proxy_gl)

    try do
      {fun.(), Proxy.stop(proxy_gl)}
    after
      Process.group_leader(self(), original_gl)
      Process.exit(proxy_gl, :kill)
    end
  end
end

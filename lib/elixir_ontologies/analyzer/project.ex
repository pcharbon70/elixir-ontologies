defmodule ElixirOntologies.Analyzer.Project do
  @moduledoc """
  Detects Mix projects and extracts project metadata.

  This module provides functions to detect Mix projects by finding mix.exs files,
  safely parse project configuration without executing arbitrary code, and extract
  project metadata including name, version, dependencies, and source directories.

  ## Usage

      iex> alias ElixirOntologies.Analyzer.Project
      iex> {:ok, project} = Project.detect(".")
      iex> is_atom(project.name)
      true

  ## Project Detection

  The `detect/1` function traverses up the directory tree looking for a `mix.exs`
  file, returning the project root path and metadata if found.

  ## Umbrella Projects

  Umbrella projects are detected by checking for:
  - The `apps_path` key in the project configuration
  - The presence of an `apps/` directory containing child projects

  ## Safety

  This module uses AST parsing (`Code.string_to_quoted/1`) to extract project
  metadata without executing any code from mix.exs files, preventing arbitrary
  code execution.
  """

  # ===========================================================================
  # Project Struct
  # ===========================================================================

  defmodule Project do
    @moduledoc """
    Represents a Mix project with its metadata.
    """

    @type t :: %__MODULE__{
            path: String.t(),
            name: atom(),
            version: String.t() | nil,
            mix_file: String.t(),
            umbrella?: boolean(),
            apps: [String.t()],
            deps: [atom() | {atom(), String.t()}],
            source_dirs: [String.t()],
            elixir_version: String.t() | nil,
            metadata: map()
          }

    @enforce_keys [:path, :name]
    defstruct [
      :path,
      :name,
      :version,
      :mix_file,
      umbrella?: false,
      apps: [],
      deps: [],
      source_dirs: [],
      elixir_version: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Project Detection
  # ===========================================================================

  @doc """
  Detects if a path is within a Mix project.

  Traverses up the directory tree looking for a `mix.exs` file and extracts
  project metadata.

  Returns `{:ok, project}` if found, `{:error, reason}` otherwise.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Project
      iex> {:ok, project} = Project.detect(".")
      iex> %ElixirOntologies.Analyzer.Project.Project{} = project
      iex> is_atom(project.name)
      true

      iex> alias ElixirOntologies.Analyzer.Project
      iex> Project.detect("/nonexistent")
      {:error, :invalid_path}
  """
  @spec detect(String.t()) :: {:ok, Project.t()} | {:error, atom()}
  def detect(path) do
    if File.exists?(path) do
      abs_path = Path.expand(path)

      with {:ok, mix_file} <- find_mix_file(abs_path),
           {:ok, config} <- parse_mix_file(mix_file) do
        build_project(Path.dirname(mix_file), mix_file, config)
      end
    else
      {:error, :invalid_path}
    end
  end

  @doc """
  Detects Mix project, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Project
      iex> project = Project.detect!(".")
      iex> is_atom(project.name)
      true
  """
  @spec detect!(String.t()) :: Project.t()
  def detect!(path) do
    case detect(path) do
      {:ok, project} -> project
      {:error, reason} -> raise "Failed to detect Mix project: #{inspect(reason)}"
    end
  end

  @doc """
  Finds the mix.exs file by traversing up the directory tree.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Project
      iex> {:ok, mix_file} = Project.find_mix_file(".")
      iex> String.ends_with?(mix_file, "mix.exs")
      true
  """
  @spec find_mix_file(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def find_mix_file(path) do
    abs_path = Path.expand(path)
    do_find_mix_file(abs_path)
  end

  @doc """
  Checks if a path is within a Mix project.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Project
      iex> Project.mix_project?(".")
      true

      iex> alias ElixirOntologies.Analyzer.Project
      iex> Project.mix_project?("/tmp")
      false
  """
  @spec mix_project?(String.t()) :: boolean()
  def mix_project?(path) do
    case find_mix_file(path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # ===========================================================================
  # Private Helpers - Mix File Detection
  # ===========================================================================

  defp do_find_mix_file(path) do
    mix_file = Path.join(path, "mix.exs")

    cond do
      File.regular?(mix_file) ->
        {:ok, mix_file}

      path == "/" or path == Path.dirname(path) ->
        {:error, :not_found}

      true ->
        do_find_mix_file(Path.dirname(path))
    end
  end

  # ===========================================================================
  # Private Helpers - Mix File Parsing
  # ===========================================================================

  defp parse_mix_file(mix_file) do
    with {:ok, content} <- File.read(mix_file),
         {:ok, ast} <- Code.string_to_quoted(content),
         {:ok, project_config} <- extract_project_config(ast) do
      {:ok, project_config}
    else
      {:error, _} = error -> error
    end
  end

  defp extract_project_config(ast) do
    case find_project_function(ast) do
      nil -> {:error, :no_project_function}
      config -> {:ok, config}
    end
  end

  # Find the def project do ... end function in the AST
  defp find_project_function({:defmodule, _, [_name, [do: body]]}) do
    find_project_function(body)
  end

  defp find_project_function({:__block__, _, expressions}) do
    Enum.find_value(expressions, &find_project_function/1)
  end

  defp find_project_function({:def, _, [{:project, _, _}, [do: body]]}) do
    extract_keyword_list(body)
  end

  defp find_project_function(_), do: nil

  # Extract keyword list from AST
  defp extract_keyword_list({:__block__, _, [expr]}) do
    extract_keyword_list(expr)
  end

  defp extract_keyword_list([{_, _} | _] = list) do
    Enum.reduce(list, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, extract_value(value))

      _, acc ->
        acc
    end)
  end

  defp extract_keyword_list(_), do: %{}

  # Extract literal values from AST
  defp extract_value({:__block__, _, [value]}), do: extract_value(value)
  defp extract_value(value) when is_atom(value), do: value
  defp extract_value(value) when is_binary(value), do: value
  defp extract_value(value) when is_number(value), do: value
  defp extract_value(value) when is_boolean(value), do: value

  # Handle lists
  defp extract_value(list) when is_list(list) do
    Enum.map(list, &extract_value/1)
  end

  # Handle function calls like deps() - just return the function name as atom
  defp extract_value({func_name, _, _}) when is_atom(func_name) do
    func_name
  end

  # Handle tuples
  defp extract_value({left, right}) do
    {extract_value(left), extract_value(right)}
  end

  # Default: return nil for complex expressions we can't safely evaluate
  defp extract_value(_), do: nil

  # ===========================================================================
  # Private Helpers - Project Building
  # ===========================================================================

  defp build_project(project_root, mix_file, config) do
    name = Map.get(config, :app)

    if name do
      umbrella? = detect_umbrella?(config, project_root)
      apps = if umbrella?, do: find_umbrella_apps(project_root, config), else: []
      source_dirs = find_source_directories(project_root, umbrella?, apps)

      project = %Project{
        path: project_root,
        name: name,
        version: Map.get(config, :version),
        mix_file: mix_file,
        umbrella?: umbrella?,
        apps: apps,
        deps: extract_deps(Map.get(config, :deps, [])),
        source_dirs: source_dirs,
        elixir_version: Map.get(config, :elixir),
        metadata: %{
          has_deps: map_size(config) > 0 and Map.has_key?(config, :deps)
        }
      }

      {:ok, project}
    else
      {:error, :no_app_name}
    end
  end

  # ===========================================================================
  # Private Helpers - Umbrella Detection
  # ===========================================================================

  defp detect_umbrella?(config, project_root) do
    has_apps_path?(config) or has_apps_directory?(project_root)
  end

  defp has_apps_path?(config) do
    Map.has_key?(config, :apps_path)
  end

  defp has_apps_directory?(project_root) do
    apps_dir = Path.join(project_root, "apps")
    File.dir?(apps_dir)
  end

  defp find_umbrella_apps(project_root, config) do
    apps_path = Map.get(config, :apps_path, "apps")
    apps_dir = Path.join(project_root, apps_path)

    if File.dir?(apps_dir) do
      apps_dir
      |> File.ls!()
      |> Enum.map(&Path.join(apps_dir, &1))
      |> Enum.filter(fn path -> File.dir?(path) and has_mix_file?(path) end)
      |> Enum.sort()
    else
      []
    end
  end

  defp has_mix_file?(dir) do
    File.regular?(Path.join(dir, "mix.exs"))
  end

  # ===========================================================================
  # Private Helpers - Dependencies
  # ===========================================================================

  defp extract_deps(:deps), do: []
  defp extract_deps(nil), do: []

  defp extract_deps(deps) when is_list(deps) do
    Enum.map(deps, &extract_dep/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_deps(_), do: []

  defp extract_dep(dep) when is_atom(dep), do: dep

  defp extract_dep({dep, version}) when is_atom(dep) and is_binary(version) do
    {dep, version}
  end

  defp extract_dep({dep, _opts}) when is_atom(dep) do
    dep
  end

  defp extract_dep(_), do: nil

  # ===========================================================================
  # Private Helpers - Source Directories
  # ===========================================================================

  defp find_source_directories(project_root, false = _umbrella?, _apps) do
    # Regular project: check lib/ and test/
    ["lib", "test"]
    |> Enum.map(&Path.join(project_root, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
  end

  defp find_source_directories(project_root, true = _umbrella?, apps) do
    # Umbrella project: include root lib/test and all app lib/test directories
    root_dirs =
      ["lib", "test"]
      |> Enum.map(&Path.join(project_root, &1))
      |> Enum.filter(&File.dir?/1)

    app_dirs =
      apps
      |> Enum.flat_map(fn app_path ->
        ["lib", "test"]
        |> Enum.map(&Path.join(app_path, &1))
        |> Enum.filter(&File.dir?/1)
      end)

    (root_dirs ++ app_dirs)
    |> Enum.sort()
    |> Enum.uniq()
  end
end

defmodule ElixirOntologies.Analyzer.ChangeTracker do
  @moduledoc """
  Tracks file changes for incremental analysis.

  This module detects file modifications, additions, and deletions by comparing
  file system state over time. This enables efficient incremental updates by
  avoiding re-analysis of unchanged files.

  ## Usage

      alias ElixirOntologies.Analyzer.ChangeTracker

      # Capture initial state
      files = ["lib/foo.ex", "lib/bar.ex"]
      old_state = ChangeTracker.capture_state(files)

      # ... time passes, files may change ...

      # Capture new state
      new_state = ChangeTracker.capture_state(files)

      # Detect all changes
      changes = ChangeTracker.detect_changes(old_state, new_state)

      changes.changed   # => ["lib/foo.ex"]  (modified)
      changes.new       # => ["lib/baz.ex"]  (added)
      changes.deleted   # => ["lib/bar.ex"]  (removed)

  ## Change Detection

  Files are considered changed if:
  - Modification time (mtime) is different
  - File size is different

  This is faster than checksum comparison while still being reliable for
  detecting modifications.

  ## State Storage

  The State struct contains:
  - `files` - Map of file_path => FileInfo
  - `timestamp` - When state was captured
  - `metadata` - Additional metadata

  State can be serialized and stored for later comparison.
  """

  # ===========================================================================
  # Structs
  # ===========================================================================

  defmodule State do
    @moduledoc """
    Snapshot of file system state at a point in time.

    ## Fields

    - `files` - Map of file_path => FileInfo structs
    - `timestamp` - Unix timestamp when state was captured
    - `metadata` - Additional metadata (project info, etc.)
    """

    @enforce_keys [:files, :timestamp]
    defstruct [
      :files,
      :timestamp,
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            files: %{String.t() => ElixirOntologies.Analyzer.ChangeTracker.FileInfo.t()},
            timestamp: integer(),
            metadata: map()
          }
  end

  defmodule FileInfo do
    @moduledoc """
    Metadata for a single file.

    ## Fields

    - `path` - Absolute file path
    - `mtime` - Modification time (Unix timestamp)
    - `size` - File size in bytes
    - `checksum` - Optional checksum (not used by default)
    """

    @enforce_keys [:path, :mtime, :size]
    defstruct [
      :path,
      :mtime,
      :size,
      checksum: nil
    ]

    @type t :: %__MODULE__{
            path: String.t(),
            mtime: integer(),
            size: non_neg_integer(),
            checksum: String.t() | nil
          }
  end

  defmodule Changes do
    @moduledoc """
    Result of change detection between two states.

    ## Fields

    - `changed` - List of files that were modified
    - `new` - List of files that were added
    - `deleted` - List of files that were removed
    - `unchanged` - List of files that haven't changed
    """

    defstruct [
      changed: [],
      new: [],
      deleted: [],
      unchanged: []
    ]

    @type t :: %__MODULE__{
            changed: [String.t()],
            new: [String.t()],
            deleted: [String.t()],
            unchanged: [String.t()]
          }
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Captures current state of given files.

  Reads file metadata (mtime, size) for each file and returns a State struct.
  Files that don't exist or can't be read are skipped.

  ## Parameters

  - `file_paths` - List of file paths to capture

  ## Returns

  State struct with current file metadata

  ## Examples

      files = ["lib/foo.ex", "lib/bar.ex"]
      state = ChangeTracker.capture_state(files)

      state.files["lib/foo.ex"]  # => %FileInfo{...}
      state.timestamp            # => 1234567890
  """
  @spec capture_state([String.t()]) :: State.t()
  def capture_state(file_paths) do
    files =
      file_paths
      |> Enum.map(&capture_file_info/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new(fn info -> {info.path, info} end)

    %State{
      files: files,
      timestamp: System.system_time(:second)
    }
  end

  @doc """
  Detects files that have changed between two states.

  A file is considered changed if:
  - It exists in both states
  - Its mtime or size is different

  ## Parameters

  - `old_state` - Previous state
  - `new_state` - Current state

  ## Returns

  List of file paths that have changed

  ## Examples

      changes = ChangeTracker.changed_files(old_state, new_state)
      # => ["lib/foo.ex", "lib/bar.ex"]
  """
  @spec changed_files(State.t(), State.t()) :: [String.t()]
  def changed_files(old_state, new_state) do
    old_state.files
    |> Enum.filter(fn {path, old_info} ->
      case Map.get(new_state.files, path) do
        nil -> false
        new_info -> file_changed?(old_info, new_info)
      end
    end)
    |> Enum.map(fn {path, _info} -> path end)
    |> Enum.sort()
  end

  @doc """
  Detects new files added since old state.

  Returns files that exist in new_state but not in old_state.

  ## Parameters

  - `old_state` - Previous state
  - `new_state` - Current state

  ## Returns

  List of file paths that were added

  ## Examples

      new_files = ChangeTracker.new_files(old_state, new_state)
      # => ["lib/new.ex"]
  """
  @spec new_files(State.t(), State.t()) :: [String.t()]
  def new_files(old_state, new_state) do
    new_state.files
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(old_state.files, &1))
    |> Enum.sort()
  end

  @doc """
  Detects files deleted since old state.

  Returns files that exist in old_state but not in new_state.

  ## Parameters

  - `old_state` - Previous state
  - `new_state` - Current state

  ## Returns

  List of file paths that were removed

  ## Examples

      deleted = ChangeTracker.deleted_files(old_state, new_state)
      # => ["lib/removed.ex"]
  """
  @spec deleted_files(State.t(), State.t()) :: [String.t()]
  def deleted_files(old_state, new_state) do
    old_state.files
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(new_state.files, &1))
    |> Enum.sort()
  end

  @doc """
  Detects all changes between two states.

  Returns a Changes struct containing:
  - changed: Modified files
  - new: Added files
  - deleted: Removed files
  - unchanged: Files that haven't changed

  ## Parameters

  - `old_state` - Previous state
  - `new_state` - Current state

  ## Returns

  Changes struct with categorized changes

  ## Examples

      changes = ChangeTracker.detect_changes(old_state, new_state)

      changes.changed    # => ["lib/foo.ex"]
      changes.new        # => ["lib/baz.ex"]
      changes.deleted    # => ["lib/bar.ex"]
      changes.unchanged  # => ["lib/qux.ex"]
  """
  @spec detect_changes(State.t(), State.t()) :: Changes.t()
  def detect_changes(old_state, new_state) do
    changed = changed_files(old_state, new_state)
    new = new_files(old_state, new_state)
    deleted = deleted_files(old_state, new_state)

    # Files that exist in both states and haven't changed
    unchanged =
      old_state.files
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(new_state.files, &1))
      |> Enum.reject(&(&1 in changed))
      |> Enum.sort()

    %Changes{
      changed: changed,
      new: new,
      deleted: deleted,
      unchanged: unchanged
    }
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp capture_file_info(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} ->
        %FileInfo{
          path: path,
          mtime: stat.mtime,
          size: stat.size
        }

      {:error, _} ->
        nil
    end
  end

  defp file_changed?(old_info, new_info) do
    old_info.mtime != new_info.mtime or old_info.size != new_info.size
  end
end

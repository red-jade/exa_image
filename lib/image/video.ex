defmodule Exa.Image.Video do
  @moduledoc """
  A command line interface for video creation 
  and frame extraction using `ffmpeg`.

  There must be an existing `ffmpeg` installation.
  `ffmpeg` is not linked and called as a library.

  https://ffmpeg.org/download.html
  """
  require Logger
  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Color.Types, as: C

  alias Exa.Image.Types, as: I
  alias Exa.Image.Image

  alias Exa.Json.Types, as: J
  alias Exa.Json.JsonReader

  # -----
  # types
  # -----

  @type exe() :: :ffmpeg | :ffprobe | :ffplay

  defguardp is_exe(e) when e in [:ffmpeg, :ffprobe, :ffplay]

  # options that are passed through to the command line
  @options [
    "c:v",
    "f",
    "i",
    "framerate",
    "loglevel",
    "loop",
    "pattern_type",
    "pix_fmt",
    "r",
    "s",
    "s:v",
    "ss",
    "start_number",
    "t",
    "x",
    "y",
    "vf",
    "volume",
    "window_title"
  ]

  # ------------
  # frame images
  # ------------

  @doc """
  Create a new image with the size of a video frame.

  The content can either be a bakcground color
  or a full image buffer matching the dimensions and given pixel format.
  """
  @spec new_frame(I.video_format(), C.pixel(), binary() | C.col3b()) :: %I.Image{}
  def new_frame(video, pix, buf_col) when is_atom(video) do
    {w, h} = video_size(video)
    Image.new(w, h, pix, buf_col)
  end

  # get the dimensions of a video frame
  @spec video_size(I.video_format()) :: {I.size(), I.size()}

  defp video_size(:video_sd), do: {640, 480}
  defp video_size(:video_480p), do: {640, 480}

  defp video_size(:video_hd), do: {1280, 720}
  defp video_size(:video_720p), do: {1280, 720}

  defp video_size(:video_fhd), do: {1920, 1080}
  defp video_size(:video_1080p), do: {1920, 1080}

  defp video_size(:video_qhd), do: {2560, 1440}
  defp video_size(:video_1440p), do: {2560, 1440}

  defp video_size(:video_2k), do: {2048, 1080}

  defp video_size(:video_4k), do: {3840, 2160}
  defp video_size(:video_uhd), do: {3840, 2160}
  defp video_size(:video_2160p), do: {3840, 2160}

  defp video_size(:video_8k), do: {7680, 4320}
  defp video_size(:video_fuhd), do: {7680, 4320}
  defp video_size(:video_4320p), do: {7680, 4320}

  defp video_size(vid) do
    msg = "Unrecognized video format #{vid}"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # --------------
  # video creation
  # --------------

  @doc "Get the ffmpeg installed executable path."
  @spec installed(exe()) :: nil | E.filename()
  def installed(exe) when is_exe(exe), do: Exa.System.installed(exe)

  @doc """
  Ensure that target executable is installed and accessible 
  on the OS command line (PATH), otherwise raise an error.
  """
  @spec ensure_installed!(exe()) :: E.filename()
  def ensure_installed!(exe) when is_exe(exe), do: Exa.System.ensure_installed!(exe)

  @doc """
  Get information about the content of a video file.

  The executable `ffprobe` must be installed 
  and available on the command line.

  If the `loglevel` is not set in the options argument, 
  it is set automatically from the Elixir `Logger.level()`.
  """
  @spec info(E.filename(), E.options()) :: J.object() | {:error, any()}
  def info(vfile, opts) when is_filename(vfile) do
    ensure_installed!(:ffprobe)
    ensure_file!(vfile)

    ents = ["-of", "json", "-show_format", "-show_streams"]
    args = ents ++ options(opts) ++ [vfile]

    Logger.info(Enum.join(["ffprobe" | args], " "))

    case System.cmd("ffprobe", args, []) do
      {output, 0} ->
        JsonReader.decode(output, object: Map)

      {msg, status} when status > 0 ->
        Logger.error("ffprobe failed [#{status}]: " <> inspect(msg))
        {:error, msg}
    end
  rescue
    err ->
      Logger.error("ffprobe error: " <> inspect(err))
      {:error, err}
  end

  @doc """
  Create a video from a sequence of frame image files.

  Keyword options follow the command line interface:

  https://ffmpeg.org/ffmpeg.html

  Except that the standalone _overwrite_ options `-y` and `-n` 
  must be specified as a kv pair in the keyword options list.

  For example: `... overwrite: "y", ...`

  Keyword keys must be atoms,
  so remember to use quoted atom literals
  when the option contains special characters.<br>
  For example: `... "c:v": "libx264", ...`

  Keys can be repeated.

  If the `loglevel` is not set in the options argument, 
  it is set automatically from the Elixir `Logger.level()`.
  """
  @spec from_files(E.filename(), E.options()) :: :ok | {:error, any()}
  def from_files(vfile, opts) when is_filename(vfile) do
    ensure_installed!(:ffmpeg)
    Exa.File.ensure_parent!(vfile)

    if Logger.compare_levels(Logger.level(), :error) == :lt do
      # use filetype, not fmt option
      {_dir, name, types} = Exa.File.split(vfile)
      type = List.last(types)
      Logger.info("Write #{String.upcase(type)} file: '#{name}.#{type}'", file: vfile)
    end

    args = options(opts) ++ [vfile]

    Logger.info(Enum.join(["ffmpeg" | args], " "))

    case System.cmd("ffmpeg", args, []) do
      {"", 0} ->
        :ok

      {msg, status} when status > 0 ->
        Logger.error("ffmpeg failed [#{status}]: " <> inspect(msg))
        {:error, msg}
    end
  rescue
    err ->
      Logger.error("ffmpeg error: " <> inspect(err))
      {:error, err}
  end

  @doc """
  Play a video from file in a pop-up viewer window.

  Keyword options follow the command line interface:

  https://ffmpeg.org/ffplay.html

  Except that the standalone `noborder` and `fs` options  
  must be specified as `"y"` or `"n"` in the keyword options list.

  For example: `... noborder: "y", ...`

  If the `loglevel` is not set in the options argument, 
  it is set automatically from the Elixir `Logger.level()`.
  """
  @spec play(E.filename(), E.options()) :: :ok | {:error, any()}
  def play(vfile, opts) when is_filename(vfile) do
    IO.puts("play")
    ensure_installed!(:ffplay)
    ensure_file!(vfile)

    {_dir, name, types} = Exa.File.split(vfile)

    if Logger.compare_levels(Logger.level(), :error) == :lt do
      # use filetype, not fmt option
      type = List.last(types)
      Logger.info("Play #{String.upcase(type)} file: '#{name}.#{type}'", file: vfile)
    end

    defs = ["-window_title", name, "-showmode", "video", "-alwaysontop"]
    args = options(opts) ++ defs ++ [vfile]

    Logger.info(Enum.join(["ffplay" | args], " "))
    IO.puts("cmd")

    case System.cmd("ffplay", args, []) do
      {"", 0} ->
        :ok

      {msg, status} when status > 0 ->
        Logger.error("ffplay failed [#{status}]: " <> inspect(msg))
        {:error, msg}
    end
  rescue
    err ->
      Logger.error("ffplay error: " <> inspect(err))
      {:error, err}
  end

  # -----------------
  # private functions
  # -----------------

  # convert keyword input options to command line arguments

  @spec options(Keyword.t()) :: [String.t()]
  defp options(opts) do
    args =
      opts
      |> Enum.reverse()
      |> Enum.reduce([], fn
        {k, v}, args ->
          case to_string(k) do
            "loglevel" -> args
            "overwrite" when v in ["y", "n"] -> ["-#{v}" | args]
            "noborder" -> if v == "y", do: ["-#{k}" | args], else: args
            "fs" -> if v == "y", do: ["-#{k}" | args], else: args
            kstr when kstr in @options -> ["-#{kstr}", "#{v}" | args]
            _ -> args
          end
      end)

    # always set the log level
    lvl = Keyword.get(opts, :loglevel, level(Logger.level()))
    ["-loglevel", lvl | args]
  end

  # convert Logger level to ffmpeg loglevel
  @dialyzer {:nowarn_function, level: 1}
  @spec level(Logger.level() | :all | :none) :: String.t()
  defp level(:none), do: "quiet"
  defp level(:emergency), do: "panic"
  defp level(:alert), do: "fatal"
  defp level(:critical), do: "fatal"
  defp level(:error), do: "error"
  defp level(:warning), do: "warning"
  defp level(:warn), do: "warning"
  defp level(:notice), do: "warning"
  # ffmpeg info is TL;DR
  defp level(:info), do: "warning"
  defp level(:debug), do: "debug"
  defp level(:all), do: "trace"

  # TODO - use version in Exa.File after roll of Exa core version

  defp ensure_file!(file) do
    if not File.exists?(file) do
      dne = "File does not exist"
      msg = dne <> ": '#{file}'"
      Logger.error(msg, file: file)
      raise File.Error, path: file, action: dne
    end
  end
end

defmodule Exa.Image.Gol do
  @moduledoc """
  A simple implementation of Conway's Game of Life.

  The grid is implemented as a bitmap. 

  Boundary conditions can be cyclic, 
  or a zero background border.

  Also see an asynchrounous implementation at the _Expaca_ project 
  ([Expaca](https://github.com/mike-french/expaca))
  """

  require Logger

  import Exa.Types
  alias Exa.Types, as: E
  alias Exa.Space.Types, as: S

  import Exa.Color.Types
  alias Exa.Color.Types, as: C
  alias Exa.Color.Col3b

  use Exa.Image.Constants

  import Exa.Image.Types
  alias Exa.Image.Types, as: I

  alias Exa.Image.Bitmap
  alias Exa.Image.Resize
  alias Exa.Image.Video
  alias Exa.Image.ImageWriter

  # default alive/dead RGB byte image pixels
  @fg Col3b.gray_pc(90)
  @bg Col3b.gray_pc(25)

  # -----
  # types
  # -----

  @typedoc """
  Boundary condition for neighborhoods
  at the edge of the frame.
  """
  @type boundary() :: :cyclic | :clamp0

  # A 2D cell location as 0-based positions.
  @typep cell() :: S.pos2i()

  # A valid cell position or `:zero` to mark a clamped border value.
  @typep neigh() :: cell() | :zero

  # The 8-neighborhood of a cell 
  # as a list of cell positions,
  # or `:zero` to mark a clamped border value.
  @typep neighborhood() :: [neigh()]

  # ----------------
  # public functions
  # ----------------

  @doc """
  Create a new random GoL grid.
  """
  @spec random(I.size(), I.size()) :: %I.Bitmap{}
  def random(w, h) when is_size(w) and is_size(h) do
    Bitmap.random(w, h)
  end

  @doc """
  Advance the GoL one step.

  The boundary condition can be either:
  - cyclic (default)
  - clamped to zero 
  """
  @spec next(%I.Bitmap{}, boundary()) :: %I.Bitmap{}
  def next(%I.Bitmap{width: w, height: h} = bmp, bound \\ :cyclic)
      when is_size(w) and is_size(h) do
    Bitmap.new(w, h, fn ij ->
      bmp
      |> neighborhood(ij, bound)
      |> Enum.reduce(0, fn
        :zero, nn -> nn
        ij, nn -> nn + Bitmap.get_bit(bmp, ij)
      end)
      |> gol_rule(Bitmap.get_bit(bmp, ij))
    end)
  end

  @spec gol_rule(0..8, E.bit()) :: bool()
  defp gol_rule(2, 1), do: true
  defp gol_rule(3, 1), do: true
  defp gol_rule(3, 0), do: true
  defp gol_rule(_, _), do: false

  @doc """
  Generate a forward sequence of frames.

  Write the images to file (png).
  Create video (mp4) animated image (gif).
  """
  @spec animate(
          E.filename(),
          E.filename(),
          %I.Bitmap{},
          E.count1(),
          boundary(),
          E.count1(),
          C.colorb(),
          C.colorb()
        ) :: :ok | {:error, any()}
  def animate(dir, name, bmp, n, bound \\ :cyclic, frate \\ 12, scale \\ 4, fg \\ @fg, bg \\ @bg)
      when is_string(dir) and is_string(name) and is_bitmap(bmp) and is_count1(n) and
             is_count1(frate) and is_colorb(fg) and is_colorb(bg) do
    dir = Path.join(dir, name)

    Enum.reduce(1..n, bmp, fn i, bmp ->
      nxt = next(bmp, bound)

      nxt 
      |> Bitmap.reflect_y()
      |> Bitmap.to_image(:rgb, fg, bg)
      |> Resize.resize(scale)
      |> ImageWriter.to_file(out_png(dir, name, i))

      nxt
    end)

    seq = out_seq(dir, name)
    mp4 = out_mp4(dir, name)
    gif = out_gif(dir, name)

    with :ok <- to_video(seq, mp4, frate),
         :ok <- to_gif(seq, gif, frate) do
      :ok
    end
  end

  # -----------------
  # private functions
  # -----------------

  # Calculate the neighborhood of a cell in the frame.
  # The neighborhood is a list of adjacent positions,
  # or a marker `:zero` for the clamped boundary.
  # The order of the positions is not specified.
  @spec neighborhood(%I.Bitmap{}, cell(), boundary()) :: neighborhood()
  defp neighborhood(%I.Bitmap{width: w, height: h}, {i, j}, bound) do
    for dj <- -1..1,
        di <- -1..1,
        not (di == 0 and dj == 0),
        ii = i + di,
        jj = j + dj,
        into: [] do
      case bound do
        :clamp0 ->
          if ii == -1 or ii == w or jj == -1 or jj == h do
            :zero
          else
            {ii, jj}
          end

        :cyclic ->
          {rem(ii + w, w), rem(jj + h, h)}
      end
    end
  end

  # png image filename
  @spec out_png(E.filename(), E.filename(), E.count1()) :: E.filename()
  defp out_png(dir, name, i) do
    n = String.pad_leading(Integer.to_string(i), 4, "0")
    Exa.File.join(dir, name <> "_" <> n, @filetype_png)
  end

  # ffmpeg compatible file sequence format
  @spec out_seq(E.filename(), E.filename()) :: E.filename()
  defp out_seq(dir, name) do
    Exa.File.join(dir, name <> "_%04d", @filetype_png)
  end

  # mp4 video filename
  @spec out_mp4(E.filename(), E.filename()) :: E.filename()
  defp out_mp4(dir, name) do
    Exa.File.join(dir, name, @filetype_mp4)
  end

  # animated gif filename
  @spec out_gif(E.filename(), E.filename()) :: E.filename()
  defp out_gif(dir, name) do
    Exa.File.join(dir, name, @filetype_gif)
  end

  @spec to_video(E.filename(), E.filename(), E.count1()) :: :ok | {:error, any()}
  defp to_video(seq, mp4, frate) do
    args = [
      loglevel: "error",
      overwrite: "y",
      i: seq,
      framerate: frate,
      r: frate,
      pattern_type: "sequence",
      start_number: "0001",
      "c:v": "libx264",
      pix_fmt: "yuv420p"
    ]

    Video.from_files(mp4, args)
  end

  @spec to_gif(E.filename(), E.filename(), E.count1()) :: :ok | {:error, any()}
  defp to_gif(seq, gif, frate) do
    args = [
      loglevel: "error",
      overwrite: "y",
      i: seq,
      framerate: frate,
      r: frate,
      pattern_type: "sequence",
      start_number: "0001",
      vf:
        "fps=#{frate},scale=100:-1:flags=lanczos," <>
          "split[s0][s1];" <>
          "[s0]palettegen[p];" <>
          "[s1][p]paletteuse"
    ]

    Video.from_files(gif, args)
  end
end

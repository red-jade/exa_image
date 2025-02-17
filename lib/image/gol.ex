defmodule Exa.Image.Gol do
  @moduledoc """
  A simple implementation of Conway's Game of Life.

  The grid is implemented as a bitmap. 

  Boundary conditions can be cyclic, 
  or a zero background border.

  Utilities are provided to write:
  - image files (png)
  - animated images (gif) and video (mp4)
    if FFMPEG is installed 

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

  import Exa.Std.Mol
  alias Exa.Std.Mol

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

  defguard is_bound(b) when b == :cyclic or b == :clamp0

  @typedoc "A 2D cell location as 0-based positions."
  @type cell() :: S.pos2i()

  @typedoc """
  The 8-neighborhood of a cell 
  as a list of cell positions
  border cells clamped to zero are omitted
  so the length of the list is `3..8`.
  """
  @type neighborhood() :: [cell()]

  @typedoc "A map of cells to their neighborhoods."
  @type neighborhoods() :: Mol.mol(cell(), cell())

  @typedoc """
  A GoL frame with a neighborhood index.
  """
  @type gol() :: {:gol, %I.Bitmap{}, neighborhoods()}

  defguard is_gol(g) when is_tuple_tag(g, 3, :gol) and is_bitmap(elem(g, 1)) and is_mol(elem(g, 2))

  # ----------------
  # public functions
  # ----------------

  @doc """
  Create a new GoL frame.

  The boundary condition can be either:
  - cyclic (default)
  - clamped to zero 
  """
  @spec new(%I.Bitmap{}, boundary()) :: gol()
  def new(%I.Bitmap{width: w, height: h}=bmp, bound) when is_bound(bound) do
    {:gol, bmp, neighborhoods(w, h, bound)}
  end

  @doc """
  Create a new random GoL frame.

  The boundary condition can be either:
  - cyclic (default)
  - clamped to zero 

  The occupancy is a number between 0.0 and 1.0,
  which specifies the probability that each cell is alive.
  """
  @spec random(I.size(), I.size(), E.unit(), boundary()) :: gol()
  def random(w, h, p \\ 0.5, bound \\ :cyclic)
      when is_size(w) and is_size(h) and is_bound(bound) and is_unit(p) do
    new(Bitmap.random(w, h, p), bound)
  end

  @doc """
  Advance the GoL one step.
  """
  @spec next(gol()) :: gol()
  def next({:gol, %I.Bitmap{width: w, height: h} = bmp, neighs})
      when is_size(w) and is_size(h) do
    next_bmp =
      Bitmap.new(w, h, fn ij ->
        neighs
        |> Mol.get(ij)
        |> Enum.reduce(0, fn loc, nn -> nn + Bitmap.get_bit(bmp, loc) end)
        |> gol_rule(Bitmap.get_bit(bmp, ij))
      end)

    {:gol, next_bmp, neighs}
  end

  @spec gol_rule(0..8, E.bit()) :: bool()
  defp gol_rule(2, 1), do: true
  defp gol_rule(3, 1), do: true
  defp gol_rule(3, 0), do: true
  defp gol_rule(_, _), do: false

  @doc """
  Generate a forward sequence of frames.

  Write the images to file (png).
  Create video (mp4) animated image (gif)
  if FFMPEG is installed.
  """
  @spec animate(
          E.filename(),
          E.filename(),
          gol(),
          E.count1(),
          boundary(),
          E.count1(),
          C.colorb(),
          C.colorb()
        ) :: :ok | {:error, any()}
  def animate(dir, name, gol, n, frate \\ 12, scale \\ 4, fg \\ @fg, bg \\ @bg)
      when is_string(dir) and is_string(name) and is_count1(n) and
             is_count1(frate) and is_colorb(fg) and is_colorb(bg) do
    dir = Path.join(dir, name)

    Enum.reduce(1..n, gol, fn i, gol ->
      next_gol = next(gol)

      next_gol
      |> elem(1)
      |> Bitmap.reflect_y()
      |> Bitmap.to_image(:rgb, fg, bg)
      |> Resize.resize(scale)
      |> ImageWriter.to_file(out_png(dir, name, i))

      next_gol
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

  # calculate neighborhoods for all cells in the frame
  @spec neighborhoods(I.size(), I.size(), boundary()) :: neighborhoods()
  defp neighborhoods(w, h, bound) do
    Enum.reduce(0..h-1, Mol.new(), fn j, mol ->
    Enum.reduce(0..w-1, mol, fn i, mol ->
      loc = {i, j}
      Mol.set(mol, loc, neighborhood(w, h, loc, bound))
    end)
  end)
  end

  # Calculate the neighborhood of a cell in the frame.
  # The neighborhood is a list of adjacent positions.
  # The order of the positions is not specified.
  @spec neighborhood(I.size(), I.size(), cell(), boundary()) :: neighborhood()

  defp neighborhood( w, h, {i, j}, :clamp0) do
    for dj <- -1..1,
        di <- -1..1,
        not (di == 0 and dj == 0),
        ii = i + di,
        jj = j + dj,
        not (ii == -1 or ii == w or jj == -1 or jj == h),
        into: [] do
      {ii, jj}
    end
  end

  defp neighborhood( w, h, {i, j}, :cyclic) do
    for dj <- -1..1,
        di <- -1..1,
        not (di == 0 and dj == 0),
        ii = i + di,
        jj = j + dj,
        into: [] do
      {rem(ii + w, w), rem(jj + h, h)}
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

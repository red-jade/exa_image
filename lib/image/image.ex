defmodule Exa.Image.Image do
  @moduledoc """
  Utilities for image buffers.

  Images use 2D integer pixel coordinates (0-based),
  and 2D integer bounding boxes for image regions.

  Sampling uses 2D float coordinates, 
  in order to specify positions between pixels.
  """
  require Logger
  use Exa.Image.Constants

  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Std.HistoTypes, as: H

  import Exa.Space.Types
  alias Exa.Space.Types, as: S

  import Exa.Color.Types
  alias Exa.Color.Types, as: C

  import Exa.Image.Types
  alias Exa.Image.Types.Image
  alias Exa.Image.Types, as: I

  alias Exa.Math
  alias Exa.Binary

  alias Exa.Std.Histo1D

  alias Exa.Space.BBox2i
  alias Exa.Space.Pos2i
  alias Exa.Color.Colorb
  alias Exa.Color.Colorf
  alias Exa.Color.Pixel

  alias Exa.Image.ImageReader
  alias Exa.Image.ImageWriter

  # ----------------
  # public functions
  # ----------------

  # -----
  # files
  # -----

  @doc """
  Write an image to file.

  Supports filetypes: BMP, TGA, TIF, PNG.
  """
  @spec to_file(%Image{}, String.t()) :: :ok
  def to_file(%Image{} = img, filename), do: ImageWriter.to_file(img, filename)

  @doc """
  Read an image from file.

  Supports filetypes: BMP, TGA, TIF, PNG, PGM, PPM.
  For filetype PBM, see `Bitmap`.
  """
  @spec from_file(String.t()) :: %Image{}
  def from_file(filename), do: ImageReader.from_file(filename)

  # ------------
  # constructors
  # ------------

  @doc """
  Create a new image with dimensions width and height.

  The image can be created from an existing buffer,
  or initialized with a background color. 

  The background color must match the number of components in the pixel.

  The buffer must have the correct size for the dimensions and pixel size.
  Pixels and rows are always aligned to bytes, so there is no padding, 
  so the formula is simple:

  `byte_size(buf) = w * h * ncomp(pix)`
  """
  @spec new(I.size(), I.size(), C.pixel(), binary() | C.colorb()) :: %Image{}

  def new(w, h, pix, buf) when is_size(w) and is_size(h) and is_binary(buf) do
    # assumes byte formats - not integer or float or 12-bit
    ncomp = Pixel.ncomp(pix)
    row = w * ncomp

    if h * row != byte_size(buf) do
      msg =
        "Buffer does not match dimensions, " <>
          "expecting #{w}x#{h}x#{ncomp}=#{h * row}, found #{byte_size(buf)}"

      Logger.error(msg)
      raise ArgumentError, message: msg
    end

    %Image{width: w, height: h, pixel: pix, ncomp: ncomp, row: row, buffer: buf}
  end

  def new(w, h, pix, bg) when is_size(w) and is_size(h) and is_colorb(bg) do
    Pixel.valid!(pix, bg)
    ncomp = Pixel.ncomp(pix)
    row = w * ncomp
    buf = clear(w, h, pix, bg)
    %Image{width: w, height: h, pixel: pix, ncomp: ncomp, row: row, buffer: buf}
  end

  # ------------
  # bounding box
  # ------------

  @doc "Get the extents of the image."
  @spec bbox(%Image{}) :: S.bbox2i()
  def bbox(%Image{width: w, height: h}), do: BBox2i.from_pos_dims({0, 0}, {w, h})

  @doc """
  Crop (clip) an image to a bounding box.

  The output image will be smaller than the requested dimensions
  when the bounds overlap the border of the target image. 
  There is no error when there is any non-zero area overlap.

  There will be an error if the requested subimage 
  is entirely outside the target image.
  """
  @spec crop(%Image{}, S.bbox2i()) :: {:ok, %Image{}} | :error
  def crop(%Image{} = img, clip) when is_bbox2i(clip) do
    {pos, dims} = img |> bbox() |> BBox2i.intersect(clip) |> elem(1) |> BBox2i.to_pos_dims()
    get_subimage(img, pos, dims)
  end

  # -------------------
  # colormap conversion
  # -------------------

  @doc """
  Convert a colormap to an RGB image.

  The orientation may be:

  `:horizontal`:

  Color variation is in the horizontal (x) direction.
  Colors are duplicated in the vertical (y) direction.
  `upsize` is x scale factor. Image width = imax*upsize.
  `dimension` is height. Image height = size.

  `:vertical`:

  Color variation is in the vertical (y) direction.
  Colors are duplicated in the horizontal (x) direction.
  `upsize` is y scale factor. Image height = imax*upsize.
  `dimension` is width. Image width = size.
  """
  @spec from_colormap(C.colormap3b(), pos_integer(), I.size(), I.orient()) :: %I.Image{}
  def from_colormap(colormap, upsize, size, orient \\ :horizontal)

  def from_colormap({:colormap, :index, :rgb, cmap}, wfac, h, :horizontal)
      when is_size(wfac) and is_size(h) do
    imax = map_size(cmap)

    row =
      Enum.reduce(0..(imax - 1), <<>>, fn i, buf ->
        chunk = cmap |> Map.fetch!(i) |> Colorb.to_bin(:rgb) |> :binary.copy(wfac)
        <<buf::binary, chunk::binary>>
      end)

    new(wfac * imax, h, :rgb, :binary.copy(row, h))
  end

  def from_colormap({:colormap, :index, :rgb, cmap}, hfac, w, :vertical)
      when is_size(w) and is_size(hfac) do
    imax = map_size(cmap) - 1

    buf =
      Enum.reduce(0..(imax - 1), <<>>, fn i, buf ->
        row = cmap |> Map.fetch!(i) |> Colorb.to_bin(:rgb) |> :binary.copy(w)
        chunk = :binary.copy(row, hfac)
        <<buf::binary, chunk::binary>>
      end)

    new(w, hfac * imax, :rgb, buf)
  end

  # -------------
  # access update
  # -------------

  @doc """
  Get a pixel value.
  Raise an error if the position is out-of-bounds.
  """
  @spec get_pixel(%Image{}, S.pos2i()) :: C.col3b()
  def get_pixel(%Image{pixel: pix, ncomp: ncomp, buffer: buf} = img, pos) when is_pos2i(pos) do
    in_bounds!(img, pos)
    lead = addr(img, pos)
    buf |> binary_part(lead, ncomp) |> Colorb.from_bin(pix) |> elem(0)
  end

  @doc "Get the sequence of pixels in an image."
  @spec get_pixels(%Image{}) :: [C.colorb()]
  def get_pixels(%Image{} = img), do: do_pix(img.buffer, img.pixel, [])

  defp do_pix(<<>>, _pix, pixels), do: Enum.reverse(pixels)

  defp do_pix(bin, pix, pixels) do
    {col, rest} = Colorb.from_bin(bin, pix)
    do_pix(rest, pix, [col | pixels])
  end

  @doc """
  Get the sequence of rows as a list of buffers.
  Take every `step` row. A step of 1 means every row.
  When `step` is more than 1, there may be residual rows 
  omitted from the end of the sequence. 
  The last row may not appear in the output. 
  """
  @spec get_rows(%Image{}, E.count1()) :: [binary()]
  def get_rows(img, step \\ 1) when is_count1(step) do
    %Image{height: height, row: row, buffer: buf} = img
    stride = step * row

    0..(height - 1)//step
    |> Enum.reduce({0, []}, fn _, {k, ps} -> {k + stride, [{buf, k, row} | ps]} end)
    |> elem(1)
    |> Enum.reverse()
    |> Binary.parts()
  end

  @doc """
  Get a subimage from the image.

  Crop the requested subimage to the bounds of the main image.
  The output image will be smaller than the requested dimensions
  when the subimage overlaps the border of the target image. 
  There is no error when there is any non-zero area overlap.

  There will be an error if the requested subimage 
  is entirely outside the target image.
  """
  @spec get_subimage(%Image{}, S.pos2i(), {I.size(), I.size()}) :: {:ok, %Image{}} | :error
  def get_subimage(%Image{} = img, pos, {w, h})
      when is_pos2i(pos) and is_size(w) and is_size(h) and w > 1 and h > 1 do
    img_bbox = bbox(img)
    sub_bbox = BBox2i.from_pos_dims(pos, {w, h})

    case BBox2i.intersect(img_bbox, sub_bbox) do
      :error ->
        :error

      {:ok, bbox} ->
        # could be the same as sub_bbox
        {new_pos, new_dims} = BBox2i.to_pos_dims(bbox)
        get_subimage!(img, new_pos, new_dims)
    end
  end

  @doc """
  Get a subimage from the image.
  The output will always have the requested dimensions.

  Raise an error if the requested subimage exceeds the bounds of the main image.
  """
  @spec get_subimage!(%Image{}, S.pos2i(), {I.size(), I.size()}) :: {:ok, %Image{}} | :error

  def get_subimage!(%Image{} = img, pos, {1, 1}) do
    in_bounds!(img, pos)
    buf = binary_part(img.buffer, addr(img, pos), img.ncomp)
    {:ok, %Image{img | :width => 1, :height => 1, :row => img.ncomp, :buffer => buf}}
  rescue
    _ -> :error
  end

  def get_subimage!(%Image{row: imgrow, buffer: imgbuf} = img, {i, j} = pos, {w, h})
      when is_pos2i(pos) and is_size(w) and is_size(h) and w > 1 and h > 1 do
    in_bounds!(img, pos)
    in_bounds!(img, {i + w - 1, j + h - 1})
    lead = addr(img, pos)
    subrow = w * img.ncomp

    {_, buf} =
      Enum.reduce(0..(h - 1), {lead, <<>>}, fn _, {k, buf} ->
        {k + imgrow, <<buf::binary, binary_part(imgbuf, k, subrow)::binary>>}
      end)

    {:ok, %Image{img | :width => w, :height => h, :row => subrow, :buffer => buf}}
  rescue
    _ -> :error
  end

  @doc "Set a pixel value."
  @spec set_pixel(%Image{}, S.pos2i(), C.colorb()) :: %Image{}
  def set_pixel(%Image{ncomp: ncomp, buffer: imgbuf, pixel: pix} = img, pos, col)
      when is_pos2i(pos) and is_colorb(col, ncomp) do
    in_bounds!(img, pos)
    lead = addr(img, pos)
    tail = tail(img, pos)
    pre = imgbuf |> binary_part(0, lead) |> Colorb.append_bin(pix, col)
    post = imgbuf |> binary_part(lead + ncomp, tail - ncomp)
    %Image{img | :buffer => <<pre::binary, post::binary>>}
  end

  @doc """
  Block transfer the subimage into the image.

  Clip the subimage to the bounds of the main image,
  so there is only an error when there is no overlap of the extents.
  """
  @spec set_subimage(%Image{}, S.pos2i(), %Image{}) :: {:ok, %Image{}} | :error
  # TODO - maybe the pos2i is really a vec2i?
  def set_subimage(%Image{} = img, {i, j} = pos, %Image{width: subw, height: subh} = sub) do
    img_bbox = bbox(img)
    sub_bbox = BBox2i.from_pos_dims(pos, {subw, subh})

    case BBox2i.intersect(img_bbox, sub_bbox) do
      :error ->
        :error

      {:ok, ^sub_bbox} ->
        set_subimage!(img, pos, sub)

      {:ok, bbox} ->
        {new_pos, new_dims} = BBox2i.to_pos_dims(bbox)
        # translate back into subimage coordinates
        {:ok, new_sub} = get_subimage(sub, Pos2i.move(new_pos, {-i, -j}), new_dims)
        set_subimage!(img, new_pos, new_sub)
    end
  end

  @doc """
  Block transfer the subimage into the image.

  Raise an error if the position and subimage extents 
  exceed the bounds of the main image.
  """
  @spec set_subimage!(%Image{}, S.pos2i(), %Image{}) :: {:ok, %Image{}} | :error
  def set_subimage!(
        %Image{ncomp: ncomp, row: imgrow, buffer: imgbuf} = img,
        {i, j} = pos,
        %Image{width: subw, height: subh, row: subrow, buffer: subbuf} = sub
      ) do
    same_pix!(img, sub)
    in_bounds!(img, pos)
    maxpos = {i + subw - 1, j + subh - 1}
    in_bounds!(img, maxpos)
    lead = addr(img, pos)
    tail = tail(img, maxpos)
    skip = imgrow - subrow

    # build edits backwards ...
    # initial prefix and first row
    parts = [{subbuf, 0, subrow}, {imgbuf, 0, lead}]

    # repeat: skip along the row and copy of next subimage row
    {k, _s, parts} =
      Enum.reduce(0..(subh - 2), {lead + subrow, subrow, parts}, fn _, {k, s, parts} ->
        {k + imgrow, s + subrow, [{subbuf, s, subrow}, {imgbuf, k, skip} | parts]}
      end)

    # the final run to the end of the main image
    parts = [{imgbuf, k, tail - ncomp} | parts]

    {:ok, %Image{img | :buffer => parts |> Enum.reverse() |> Binary.merge()}}
  rescue
    _ -> :error
  end

  # --------------
  # reflect rotate
  # --------------

  @doc "Reflect the image in the y-direction."
  @spec reflect_y(%Image{}) :: %Image{}
  def reflect_y(%Image{} = img) do
    buf = img |> get_rows() |> Enum.reverse() |> Binary.concat()
    %Image{img | :buffer => buf}
  end

  @doc "Reflect the image in the x-direction."
  @dialyzer {:no_return, reflect_x: 1}
  @spec reflect_x(%Image{}) :: %Image{}
  def reflect_x(%Image{} = img) do
    buf = img |> get_rows() |> Enum.map(&reverse(&1, img.ncomp)) |> Binary.concat()
    %Image{img | :buffer => buf}
  end

  @doc "Rotate the image 90 degrees clockwise (270 degrees anti-clockwise)."
  @dialyzer {:no_return, rotate_90: 1}
  @spec rotate_90(%Image{}) :: %Image{}
  def rotate_90(%Image{} = img) do
    buf = img |> get_rows() |> zip(img.ncomp * 8, [], false)
    %Image{img | :buffer => buf}
  end

  @doc "Rotate the image 180 degrees."
  @dialyzer {:no_return, rotate_180: 1}
  @spec rotate_180(%Image{}) :: %Image{}
  def rotate_180(%Image{} = img) do
    buf =
      img
      |> get_rows()
      |> Enum.reverse()
      |> Enum.map(&reverse(&1, img.ncomp))
      |> Binary.concat()

    %Image{img | :buffer => buf}
  end

  @doc "Rotate the image 270 degrees clockwise (90 degrees anti-clockwise)."
  @dialyzer {:no_return, rotate_270: 1}
  @spec rotate_270(%Image{}) :: %Image{}
  def rotate_270(%Image{} = img) do
    buf = img |> get_rows() |> zip(img.ncomp * 8, [], true)
    %Image{img | :buffer => buf}
  end

  # ---------
  # histogram
  # ---------

  # TODO - HSL conversions
  # TODO - 2D and 3D histograms ... then color correction

  @doc "A 1D histogram of one color channel in an image."
  @spec histogram(%Image{}, C.channel()) :: H.histo1d()
  def histogram(img, chan) do
    fun = fn col, pix, histo -> Histo1D.inc(histo, Pixel.component(col, pix, chan)) end
    reduce_pixels(img, Histo1D.new(256), fun)
  end

  # ---------------
  # split and merge
  # ---------------

  @doc """
  Split an image into a specified number of image chunks.

  Each chunk is a contiguous sequence of whole rows.
  The maximum number of chunks is the height of the image,
  when each chunk is exactly 1 row.

  If the image height is not evenly divisible by the number of chunks,
  then the last chunk will have the remainder rows, 
  and will be smaller than the others.

  If the number _n_ is given as `:nproc` (default),
  then the number of logical processors on the cpu hardware is used.
  The value `:nproc2` means double the number of processors.
  """
  @spec split_n(%Image{}, I.npara()) :: [%Image{}]
  def split_n(img, n \\ :nproc)
  def split_n(img, :nproc), do: split_n(img, Exa.System.n_processors())
  def split_n(img, :nproc2), do: split_n(img, 2 * Exa.System.n_processors())
  def split_n(img, 1), do: [img]

  def split_n(%Image{buffer: buf} = img, n) when is_count2(n) do
    chunk_size = Binary.chunk_size(byte_size(buf), n)
    split(img, chunk_size)
  end

  @doc """
  Split an image into image chunks with a specified chunk size (in bytes).

  If the chunk size is bigger than the image,
  then the whole image will be returned in a singleton list.

  If the chunk_size is smaller than the row size,
  then the image will be split into individual `1 x h` row images.
  """
  @spec split(%Image{}, E.bsize()) :: [%Image{}]
  def split(%Image{row: row, buffer: buf} = img, chunk_size) do
    buf
    |> Binary.split(row, chunk_size)
    |> Enum.map(fn b -> %Image{img | :height => div(byte_size(b), row), :buffer => b} end)
  end

  @doc """
  Merge images into a single image.

  The pixel type and width (hence ncomp and row size),
  must be the same for all the images.
  The final height will be the sum of the heights of the inputs.
  """
  @spec merge([%Image{}]) :: %Image{}
  def merge([%Image{width: w, pixel: pix, row: row, ncomp: ncomp} = img1 | _] = images) do
    {h, bufs} =
      Enum.reduce(images, {0, []}, fn
        %Image{width: ^w, pixel: ^pix, row: ^row, ncomp: ^ncomp} = img, {h, bufs} ->
          {h + img.height, [img.buffer | bufs]}
      end)

    buffer = bufs |> Enum.reverse() |> Binary.concat()
    %Image{img1 | :height => h, :buffer => buffer}
  end

  # ---------------
  # matte and alpha 
  # ---------------

  @doc """
  Expand a bitmap as an alpha component in an image. 

  The bitmap and the image must have the same dimensions.

  The input image must be compatible with the specified output pixel format.
  There are three kinds of options for the image pixel format:
  - `:grey` -> `:grey_alpha` or `:alpha_grey` _TODO_ when 2-byte images are added
  - `:rgb` -> `:rgba` or `:argb`
  - `:bgr` -> `:abgr` or `:bgra` 
  """
  @spec bitmap_alpha(%I.Bitmap{}, %I.Image{}, C.pixel()) :: %I.Image{}

  def bitmap_alpha(
        %I.Bitmap{width: w, height: h, row: brow, buffer: bbuf},
        %I.Image{width: w, height: h, pixel: img_pix, row: irow, buffer: ibuf},
        out_pix
      )
      when (img_pix == :rgb and out_pix in [:rgba, :argb]) or
             (img_pix == :bgr and out_pix in [:bgra, :abgr]) do
    {<<>>, <<>>, out} =
      Enum.reduce(0..(h - 1), {bbuf, ibuf, <<>>}, fn _, {bbuf, ibuf, out} ->
        {browbuf, brest} = Binary.take(bbuf, brow)
        {irowbuf, irest} = Binary.take(ibuf, irow)

        {_bpad, <<>>, out} =
          Enum.reduce(0..(w - 1), {browbuf, irowbuf, out}, fn
            _, {<<b::1, browrest::bits>>, irowbuf, out} ->
              a = if b == 0, do: 0, else: 255
              {col, irowrest} = Colorb.from_bin(irowbuf, img_pix)
              cola = Pixel.add_alpha(col, a, out_pix)
              out = Colorb.append_bin(out, out_pix, cola)
              {browrest, irowrest, out}
          end)

        {brest, irest, out}
      end)

    new(w, h, out_pix, out)
  end

  @doc """
  Use a bitmap to control a composite of two images.
  The first image is the foreground, the second image is the background.
  A bitmap value of `1` selects foreground, 
  a value of `0` selects background.

  The bitmap and the images must all have the same dimensions.

  The images must have the same pixel format. 
  """
  @spec matte(matte :: %I.Bitmap{}, fg :: %I.Image{}, bg :: %I.Image{}) :: %I.Image{}

  def matte(
        %I.Bitmap{width: w, height: h, row: brow, buffer: bbuf},
        %I.Image{width: w, height: h, pixel: pix, row: row, buffer: i1buf},
        %I.Image{width: w, height: h, pixel: pix, row: row, buffer: i2buf}
      ) do
    {<<>>, <<>>, <<>>, out} =
      Enum.reduce(0..(h - 1), {bbuf, i1buf, i2buf, <<>>}, fn _, {bbuf, i1buf, i2buf, out} ->
        {browbuf, brest} = Binary.take(bbuf, brow)
        {i1rowbuf, i1rest} = Binary.take(i1buf, row)
        {i2rowbuf, i2rest} = Binary.take(i2buf, row)

        {_bpad, <<>>, <<>>, out} =
          Enum.reduce(0..(w - 1), {browbuf, i1rowbuf, i2rowbuf, out}, fn
            _, {<<b::1, browrest::bits>>, i1rowbuf, i2rowbuf, out} ->
              {col1, i1rowrest} = Colorb.from_bin(i1rowbuf, pix)
              {col2, i2rowrest} = Colorb.from_bin(i2rowbuf, pix)
              col = if b == 0, do: col2, else: col1
              out = Colorb.append_bin(out, pix, col)
              {browrest, i1rowrest, i2rowrest, out}
          end)

        {brest, i1rest, i2rest, out}
      end)

    new(w, h, pix, out)
  end

  @doc """
  Alpha blend two images. 
  The first image is the foreground (source, src).
  The second image is the background (destination, dst).

  The images must have the same dimensions.

  The image pixel formats must comply with the alpha blend function.
  The images do not necessarily have to have an alpha channel,
  but if there is no alpha channel, then:
  - the blend function cannot reference _src alpha_ or _dst alpha_
  - the blend function should use alpha `one`, `zero` 
    or provide constant alpha values

  The output image will have the same pixel format as the background (destination).
  """
  @spec alpha_blend(src :: %I.Image{}, dst :: %I.Image{}, C.blend_mode()) :: %I.Image{}
  def alpha_blend(
        %I.Image{width: w, height: h, pixel: src_pix, row: src_row, buffer: srcbuf},
        %I.Image{width: w, height: h, pixel: dst_pix, row: dst_row, buffer: dstbuf},
        mode
      ) do
    # could optimize this for images that have no row padding
    # by just reducing over all pixels, not by rows,
    # buy this structure will support row padding in the future 
    # (e.g. 10- or 12-bit colors)
    {<<>>, <<>>, out} =
      Enum.reduce(0..(h - 1), {srcbuf, dstbuf, <<>>}, fn _, {srcbuf, dstbuf, out} ->
        {srcrowbuf, srcrest} = Binary.take(srcbuf, src_row)
        {dstrowbuf, dstrest} = Binary.take(dstbuf, dst_row)

        {<<>>, <<>>, out} =
          Enum.reduce(0..(w - 1), {srcrowbuf, dstrowbuf, out}, fn _,
                                                                  {srcrowbuf, dstrowbuf, out} ->
            {src, srcrowrest} = Colorb.from_bin(srcrowbuf, src_pix)
            {dst, dstrowrest} = Colorb.from_bin(dstrowbuf, dst_pix)
            col = Pixel.alpha_blend(src, src_pix, dst, dst_pix, mode)
            out = Colorb.append_bin(out, dst_pix, col)
            {srcrowrest, dstrowrest, out}
          end)

        {srcrest, dstrest, out}
      end)

    new(w, h, dst_pix, out)
  end

  # ---------------------------
  # sampling filtering resizing
  # ---------------------------

  @doc """
  Sample the image using floating-point coordinates.

  If `normalize?` is `true`, position values in the range
  (0.0,1.0) are mapped to the whole width and height of the image.
  Values outside the range (0.0,1.0) are handled according to the `wrap` argument.

  If `normalize?` is `false`, positions are interpreted as pixel coordinates
  with ranges x: (0.0,width-1.0) and y: (0.0,height-1.0).
  Values outside these ranges are handled according to the `wrap` argument.
  """

  @spec sample(%Image{}, S.pos2f(), bool(), I.wrap(), I.interp()) :: C.color()
  def sample(img, pos, normalized? \\ true, wrap \\ :wrap_repeat, interp \\ :interp_nearest)

  def sample(%Image{} = img, {x, y}, false, wrap, interp) do
    sample(img, {x / img.width, y / img.height}, true, wrap, interp)
  end

  def sample(%Image{width: w, height: h} = img, {u, v}, true, wrap, interp) do
    # IO.inspect({w, h}, label: "w h")
    # IO.inspect({u, v}, label: "u v")

    # input {u,v} will map unit range to the whole image
    # but they can still be < 0.0 or > 1.0
    # so convert to strict range (0.0, 1.0) 
    {u, v} =
      case wrap do
        :wrap_repeat -> {Math.frac(u), Math.frac(v)}
        :wrap_repeat_mirror -> {Math.frac_mirror(u), Math.frac_mirror(v)}
        :wrap_clamp_edge -> {Math.clamp_(0.0, u, 1.0), Math.clamp_(0.0, v, 1.0)}
      end

    assert_normalized!(u, v)
    # IO.inspect({u, v}, label: "u v")

    # scale back to pixel space
    x = u * w
    y = v * h
    # IO.inspect({x, y}, label: "x y")

    case interp do
      :interp_nearest ->
        nearest = {Math.clamp_(0, trunc(x), w - 1), Math.clamp_(0, trunc(y), h - 1)}
        get_pixel(img, nearest)

      :interp_linear ->
        bilinear({x, y}, w, h)
        |> Enum.map(fn {w, pos} -> {w, get_pixel(img, pos)} end)
        |> Colorf.blend()
    end
  end

  @doc """
  Expand an indexed image by looking up colors in a colormap.
  The final image will have a pixel shape 
  determined by the values of the colormap. 
  Typically, the output will be 3-byte RGB or 4-byte RGBA.
  """
  @spec map_colors(%Image{}, C.colormap()) :: %Image{}
  def map_colors(%Image{pixel: :index} = img, {:colormap, :index, dst, cmap}) do
    map_pixels(img, {:index, &Map.fetch!(cmap, &1), dst})
  end

  @doc """
  Map a pixel function (color-color) across the whole image.
  The output image has the same dimensions as the input image.

  The pixel function may have different types for input and output.

  The src (input) format is specified in the (optional) `src_pix` pixel argument.
  If the src is `nil` then the src pixel is assumed to be the same as the image pixel.

  The dst (output) format is specified in the (optional) `dst_pix` pixel argument.
  If the dst is `nil` then the dst pixel is assumed to be the same as the src pixel.
  """
  @spec map_pixels(%Image{}, C.pixel_fun()) :: %Image{}

  def map_pixels(%Image{pixel: img_pix} = img, fun) when is_function(fun, 1) do
    map_pixels(img, {img_pix, fun, img_pix})
  end

  def map_pixels(%Image{pixel: img_pix, buffer: buf} = img, {src_pix, pix_fun, dst_pix})
      when is_pixfun(src_pix, pix_fun, dst_pix) do
    src_pix = if is_nil(src_pix), do: img_pix, else: src_pix
    dst_pix = if is_nil(dst_pix), do: src_pix, else: dst_pix
    new_buf = map_pixbuf(buf, {src_pix, pix_fun, dst_pix}, <<>>)
    %Image{img | :pixel => dst_pix, :buffer => new_buf}
  end

  @spec map_pixbuf(binary(), C.pixel_fun(), binary()) :: binary()

  defp map_pixbuf(<<>>, _pixfun, out), do: out

  defp map_pixbuf(buf, {src_pix, pix_fun, dst_pix}, out) do
    {col, rest} = Colorb.from_bin(buf, src_pix)
    out = Colorb.append_bin(out, dst_pix, pix_fun.(col))
    map_pixbuf(rest, {src_pix, pix_fun, dst_pix}, out)
  end

  @doc """
  Reduce over pixels of an image. 

  Apply a reduce function to accumulate a new output structure.
  The function takes three arguments:
  - color byte data
  - pixel format
  - current output data
  The output must be the updated output data.
  """
  @spec reduce_pixels(%Image{}, t, (C.color(), C.pixel(), t -> t)) :: t when t: var
  def reduce_pixels(%Image{pixel: pix, buffer: buf}, init, fun) do
    reduce_pixbuf(buf, pix, fun, init)
  end

  @spec reduce_pixbuf(binary(), C.pixel(), fun(), any()) :: any()

  defp reduce_pixbuf(<<>>, _pix, _pixfun, out), do: out

  defp reduce_pixbuf(buf, pix, fun, out) do
    {col, rest} = Colorb.from_bin(buf, pix)
    reduce_pixbuf(rest, pix, fun, fun.(col, pix, out))
  end

  # -----------------
  # private functions
  # -----------------

  # test bounds for public function
  @spec in_bounds!(%Image{}, S.pos2i()) :: nil
  defp in_bounds!(%Image{width: w, height: h}, {i, j}) do
    if i < 0 or i >= w or j < 0 or j >= h do
      msg =
        "Image coordinates out of bounds, " <>
          "dimensions (0..#{w - 1}, 0..#{h - 1}), position {#{i},#{j}}."

      Logger.error(msg)
      raise ArgumentError, message: msg
    end
  end

  # test pixels for public function
  @spec same_pix!(%Image{}, %Image{}) :: nil
  defp same_pix!(%Image{pixel: pix1}, %Image{pixel: pix2}) do
    if pix1 != pix2 do
      msg = "Pixel formats are not the same, expecting #{pix1}, found #{pix2}"
      Logger.error(msg)
      raise ArgumentError, message: msg
    end
  end

  # inline assertion 
  @spec assert_bounds!(integer(), integer(), I.size(), I.size()) :: true
  defp assert_bounds!(i, j, w, h) do
    true = 0 <= i and i < w and 0 <= j and j < h
  end

  # inline assertion
  @spec assert_normalized!(float(), float()) :: true
  defp assert_normalized!(u, v) do
    true = 0.0 <= u and u <= 1.0 and 0.0 <= v and v <= 1.0
  end

  # create a new buffer filled with a background color
  @spec clear(I.size(), I.size(), C.pixel(), C.colorb()) :: binary()
  defp clear(w, h, pix, col) do
    true = is_colorb(col, Pixel.ncomp(pix))
    Enum.reduce(1..(w * h), <<>>, fn _, buf -> Colorb.append_bin(buf, pix, col) end)
  end

  # byte offset address (1-based prefix length) of a position in the buffer
  @spec addr(%Image{}, S.pos2i()) :: E.bsize()
  defp addr(img, {i, j}), do: i * img.ncomp + j * img.row

  # byte tail length from a position to the end of the buffer
  @spec tail(%Image{}, S.pos2i()) :: E.bsize()
  defp tail(%Image{} = img, {i, j}), do: addr(img, {img.width - i, img.height - j - 1})

  # reverse a buffer using the pixel size"
  @dialyzer {:no_return, reverse: 2}
  @spec reverse(binary(), C.ncomp()) :: binary()
  defp reverse(buf, ncomp), do: rev(buf, ncomp * 8, [])

  @dialyzer {:no_return, rev: 3}
  @spec rev(binary(), C.ncomp(), [binary()]) :: binary()

  defp rev(<<>>, _ncomp, rev), do: Binary.concat(rev)

  defp rev(buf, ncomp8, rev) do
    <<pix::ncomp8*1, rest::binary>> = buf
    rev(rest, ncomp8, [<<pix::ncomp8*1>> | rev])
  end

  # zip buffers together
  # take the first pixel from each buffer to form a new row
  # continue until all the buffers are empty
  # all the buffers should be the same size
  @spec zip([binary()], C.ncomp(), [binary()], bool()) :: binary()

  defp zip(bufs, _, rows, flipx?) when hd(bufs) == "" do
    # default reverse, so not flip the rows (reflect_y) for 270 rotation
    rows = if flipx?, do: rows, else: Enum.reverse(rows)
    Binary.concat(rows)
  end

  defp zip(bufs, ncomp8, rows, flipx?) do
    {row, rests} =
      Enum.reduce(bufs, {[], []}, fn
        <<pix::ncomp8*1, rest::binary>>, {row, rests} ->
          {[<<pix::ncomp8*1>> | row], [rest | rests]}
      end)

    # flip the row (reflect_x) for 270 rotation
    row = if flipx?, do: Enum.reverse(row), else: row

    zip(Enum.reverse(rests), ncomp8, [Binary.concat(row) | rows], flipx?)
  end

  # calculate 2x2 box based on pixel centres
  # low fraction 0.0-0.5 will get i-1, i
  # high fraction 0.5-1.0 will get i, i+1
  # out of bounds values get clamped to border
  # so within (0.5,0.5) of corners will get 4 copies of corner pixel
  # e.g. {0.1,0.2} gets four copies of {0,0}
  # could be made more efficient by special casing corners and edges
  # but gain will go down as size of the image increases 
  # as most pixels will be in the central zone

  @spec bilinear(S.pos2f(), I.size(), I.size()) :: [{E.unit(), S.pos2i()}]
  defp bilinear({x, y}, w, h) do
    # IO.inspect({x, y}, label: "box x y")
    i1 = trunc(x - 0.5)
    j1 = trunc(y - 0.5)
    assert_bounds!(i1, j1, w, h)

    i2 = Math.clamp_(0, trunc(x + 0.5), w - 1)
    j2 = Math.clamp_(0, trunc(y + 0.5), h - 1)
    assert_bounds!(i2, j2, w, h)

    xf = Math.frac(x - 0.5)
    yf = Math.frac(y - 0.5)
    xfyf = xf * yf

    [
      # (1 - xf) * (1 - yf)
      {1 - xf - yf + xfyf, {i1, j1}},
      # (1 - xf) * yf
      {yf - xfyf, {i2, j1}},
      # xf * (1 - yf )
      {xf - xfyf, {i1, j2}},
      # xf * yf
      {xfyf, {i2, j2}}
    ]
  end
end

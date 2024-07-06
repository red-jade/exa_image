defmodule Exa.Image.Bitmap do
  @moduledoc "Utilities for bitmap buffers."

  require Logger
  use Exa.Image.Constants

  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Color.Types, as: C

  import Exa.Space.Types
  alias Exa.Space.Types, as: S

  import Exa.Image.Types
  alias Exa.Image.Types, as: I

  require Exa.Binary
  alias Exa.Binary

  alias Exa.Color.Pixel
  alias Exa.Color.Colorb
  alias Exa.Space.BBox2i

  alias Exa.Image.Image

  # ----------------
  # public functions
  # ----------------

  @doc """
  Create a new 2D bitmap with dimensions width and height.

  The image can be created from either:
  - an existing buffer
  - initialized with a background bit value (0,1)
  - predicate function that returns a bit for each location
  """
  @spec new(I.size(), I.size(), binary() | E.bit() | E.predicate?(S.pos2i())) :: %I.Bitmap{}

  def new(w, h, buf) when is_size(w) and is_size(h) and is_binary(buf) do
    row = Binary.padded_bits(w)

    if h * row != byte_size(buf) do
      msg =
        "Buffer does not match dimensions, " <>
          "expecting #{h} * pad(#{w}) = #{h * row}, found #{byte_size(buf)}"

      Logger.error(msg)
      raise ArgumentError, message: msg
    end

    %I.Bitmap{width: w, height: h, row: row, buffer: buf}
  end

  def new(w, h, b) when is_size(w) and is_size(h) and is_bit(b) do
    row = Binary.padded_bits(w)
    buf = clear(row, h, b)
    %I.Bitmap{width: w, height: h, row: row, buffer: buf}
  end

  def new(w, h, f) when is_size(w) and is_size(h) and is_pred(f) do
    row = Binary.padded_bits(w)
    pad = Binary.pad_bits(w)

    buf =
      Enum.reduce(0..(h - 1), <<>>, fn j, buf ->
        row =
          Enum.reduce(0..(w - 1), buf, fn i, buf ->
            b = if f.({i, j}), do: 1, else: 0
            <<buf::bits, b::1>>
          end)

        <<row::bits, 0::size(pad)>>
      end)

    %I.Bitmap{width: w, height: h, row: row, buffer: buf}
  end

  @doc "Get the extents of the bitmap."
  @spec bbox(%I.Bitmap{}) :: S.bbox2i()
  def bbox(%I.Bitmap{width: w, height: h}), do: BBox2i.from_pos_dims({0, 0}, {w, h})

  @doc """
  Get a bit value.

  Raise an error if the position is out-of-bounds.
  """
  @spec get_bit(%I.Bitmap{}, S.pos2i()) :: E.bit()
  def get_bit(%I.Bitmap{buffer: buf} = bmp, pos) when is_pos2i(pos) do
    in_bounds!(bmp, pos)
    Binary.bit(buf, addr(bmp, pos))
  end

  @doc """
  Set a bit in a Bitmap.

  Raise an error if the position is out-of-bounds.
  """
  @spec set_bit(%I.Bitmap{}, S.pos2i(), E.bit()) :: %I.Bitmap{}
  def set_bit(%I.Bitmap{buffer: buf} = bmp, pos, b) when is_bit(b) do
    in_bounds!(bmp, pos)
    new_buf = Binary.set_bit(buf, addr(bmp, pos), b)
    %I.Bitmap{bmp | :buffer => new_buf}
  end

  @doc """
  Get the sequence of bit values in a Bitmap.

  Result is a list of rows, 
  where each row is a list of bit integers.
  """
  @spec get_bits(%I.Bitmap{}) :: [[E.bit()]]
  def get_bits(%I.Bitmap{width: w, height: h, row: row, buffer: buf}) do
    {<<>>, blist} =
      Enum.reduce(1..h, {buf, []}, fn _, {buf, blist} ->
        {row_buf, rest} = Binary.take(buf, row)
        row_bits = Binary.take_bits(row_buf, w)
        {rest, [row_bits | blist]}
      end)

    Enum.reverse(blist)
  end

  @doc "Reflect the bitmap in the y-direction."
  @spec reflect_y(%I.Bitmap{}) :: %I.Bitmap{}

  def reflect_y(%I.Bitmap{row: 1, buffer: buf} = bmp) do
    buf = buf |> Binary.to_bytes() |> Enum.reverse() |> Binary.from_bytes()
    %I.Bitmap{bmp | :buffer => buf}
  end

  def reflect_y(%I.Bitmap{} = bmp) do
    buf = bmp |> get_rev_rows() |> Binary.concat()
    %I.Bitmap{bmp | :buffer => buf}
  end

  @doc "Reflect the bitmap in the x-direction."
  @spec reflect_x(%I.Bitmap{}) :: %I.Bitmap{}

  def reflect_x(%I.Bitmap{width: w} = bmp) when Binary.rem8(w) == 0 do
    buf =
      bmp
      |> get_rev_rows()
      |> Enum.reverse()
      |> Enum.map(&Binary.reverse_bits/1)
      |> Binary.concat()

    %I.Bitmap{bmp | :buffer => buf}
  end

  def reflect_x(%I.Bitmap{width: w, row: row} = bmp) do
    pad = 8 * row - w

    buf =
      bmp
      |> get_rev_rows()
      |> Enum.reverse()
      |> Enum.map(&mask_reverse_bits(&1, w, pad))
      |> Binary.concat()

    %I.Bitmap{bmp | :buffer => buf}
  end

  @spec mask_reverse_bits(binary(), E.bsize(), E.bsize()) :: binary()
  defp mask_reverse_bits(buf, nbits, pad) when pad > 0 do
    <<data::size(nbits)-bits, _::size(pad)>> = buf
    atad = Binary.reverse_bits(data)
    <<atad::size(nbits)-bits, 0::size(pad)>>
  end

  @doc """
  Reduce a function over the bits of a bitmap.

  The bit reducer function must have signature:

  `bitfun(i :: E.index0(), j :: E.index0(), b :: bit(), out :: any() ) :: any()`
  """
  @spec reduce(%I.Bitmap{}, a, (E.index0(), E.index0(), E.bit(), a -> a)) :: a when a: var
  def reduce(%I.Bitmap{width: w, height: h, row: row, buffer: buf}, init, bitfun) do
    pad = 8 * row - w

    {<<>>, out} =
      Enum.reduce(0..(h - 1), {buf, init}, fn j, {buf, out} ->
        {<<_::size(pad)-bits, rest::bits>>, out} =
          Enum.reduce(0..(w - 1), {buf, out}, fn
            i, {<<b::1, rest::bits>>, out} -> {rest, bitfun.(i, j, b, out)}
          end)

        {rest, out}
      end)

    out
  end

  @doc """
  Convert the bitmap to a String, 
  using foreground and background characters.

  The String is generated in row-major order,
  with the origin in the top-left corner
  (j=0 row first).
  The printed appearance will be consistent with
  image-based graphics and fonts,
  but reversed (flipped j-direction) with respect to 
  vector graphics systems (e.g. OpenGL).

  Default characters are: `'X'` (1) and `'.'` (0).

  Rows end with a single newline.
  """
  @spec to_ascii(%I.Bitmap{}, char(), char()) :: String.t()
  def to_ascii(%I.Bitmap{} = bmp, fg \\ ?X, bg \\ ?.) do
    out =
      reduce(bmp, <<>>, fn i, j, b, out ->
        c = if b === 0, do: bg, else: fg
        out = if i == 0 and j > 0, do: <<out::binary, ?\n>>, else: out
        <<out::binary, c>>
      end)

    <<out::binary, ?\n>>
  end

  @doc """
  Convert a String to a bitmap,
  testing for foreground and background characters.

  The String is consumed in row-major order,
  with the origin in the top-left corner
  (j=0 row first).

  Default characters are: `'X'` (1) and `'.'` (0).

  Rows end with a single newline `'\\n'`.
  """
  @spec from_ascii(String.t(), I.size(), I.size(), char(), char()) :: %I.Bitmap{}
  def from_ascii(str, w, h, fg \\ ?X, bg \\ ?.)
      when is_string(str) and
             is_size(w) and is_size(h) and
             is_char(fg) and is_char(bg) and
             byte_size(str) == h * (w + 1) do
    row = Binary.padded_bits(w)
    pad = Binary.pad_bits(w)
    buf = asc(str, 0, 0, fg, bg, pad, <<>>)
    %I.Bitmap{width: w, height: h, row: row, buffer: buf}
  end

  @spec asc(String.t(), non_neg_integer(), non_neg_integer(), char(), char(), E.bsize(), E.bits()) ::
          E.bits()
  defp asc(<<c, rest::binary>>, i, j, fg, bg, pad, buf) do
    case c do
      ^bg -> asc(rest, i + 1, j, fg, bg, pad, <<buf::bits, 0::1>>)
      ^fg -> asc(rest, i + 1, j, fg, bg, pad, <<buf::bits, 1::1>>)
      ?\n when pad == 0 -> asc(rest, 0, j + 1, fg, bg, pad, buf)
      ?\n -> asc(rest, 0, j + 1, fg, bg, pad, <<buf::bits, 0::size(pad)>>)
    end
  end

  defp asc(<<>>, _i, _j, _fg, _bg, _pad, buf), do: buf

  @doc """
  Convert the bitmap to an Image, 
  using foreground and background byte colors.
  The colors must be compatible with the specified pixel format.
  """
  @spec to_image(%I.Bitmap{}, C.pixel(), C.colorb(), C.colorb()) :: %I.Image{}
  def to_image(%I.Bitmap{width: w, height: h} = bmp, pix, fg, bg) do
    Pixel.valid!(pix, fg)
    Pixel.valid!(pix, bg)

    buf =
      reduce(bmp, <<>>, fn _i, _j, b, out ->
        col = if b === 0, do: bg, else: fg
        Colorb.append_bin(out, pix, col)
      end)

    Image.new(w, h, pix, buf)
  end

  # -----------------
  # private functions
  # -----------------

  # test bounds for public function
  @spec in_bounds!(%I.Bitmap{}, S.pos2i()) :: nil
  defp in_bounds!(%I.Bitmap{width: w, height: h}, {i, j}) do
    if i < 0 or i >= w or j < 0 or j >= h do
      msg =
        "Bitmap coordinates out of bounds, " <>
          "dimensions (0..#{w - 1}, 0..#{h - 1}), position {#{i},#{j}}."

      Logger.error(msg)
      raise ArgumentError, message: msg
    end
  end

  # create a new buffer filled with a background value
  # note that pad bits also get the background value
  @spec clear(E.bsize(), I.size(), E.bit()) :: binary()
  defp clear(row, h, b) do
    byte = if b == 0, do: 0x00, else: 0xFF
    Enum.reduce(1..(h * row), <<>>, fn _, buf -> <<buf::binary, byte::8>> end)
  end

  # get the sequence of rows as a reversed list of buffers.
  @spec get_rev_rows(%I.Bitmap{}) :: [binary()]
  defp get_rev_rows(%I.Bitmap{height: height, row: row, buffer: buf}) do
    0..(height - 1)
    |> Enum.reduce({0, []}, fn _, {k, ps} -> {k + row, [{buf, k, row} | ps]} end)
    |> elem(1)
    |> Binary.parts()
  end

  # {byte, bit} offset address (prefix length) of a position in the buffer
  @spec addr(%I.Bitmap{}, S.pos2i()) :: {nbyte :: E.index0(), nbit :: E.index0()}
  defp addr(%I.Bitmap{row: row}, {i, j}), do: {j * row + Binary.div8(i), Binary.rem8(i)}
end

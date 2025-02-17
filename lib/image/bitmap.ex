defmodule Exa.Image.Bitmap do
  @moduledoc """
  Utilities for 2D bitmap buffers.

  Bits are stored in a binary buffer in row-major order.
  Rows are padded up to the next 8-bit boundary.

  Positions are 2D using 0-based integers.

  A row is described as the x-direction 
  Position within the row uses index _i._
  A value of _i_ specifies a column of bits in the bitmap.
  For bitmap width _w_ the index range is `0 <= i <= (w-1)`.

  The row sequence is described as the y-direction.
  Position within the column uses index _j._
  A value of _j_ specifies a row of bits in the bitmap.
  For bitmap height _h_ the index range is `0 <= j <= (h-1)`.

  Random access to a bit is O(1).
  """

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

  # -----
  # types
  # -----

  @typedoc "A set of locations in a 2D image or bitmap."
  @type bitset() :: MapSet.t(S.pos2i())

  @typedoc "A predicate that returns a boolean value for each location."
  @type bit_predicate() :: E.predicate?(S.pos2i())

  @typedoc "A reducer function for updating state at each location and value."
  @type bit_reducer(a) :: (E.index0(), E.index0(), E.bit(), a -> a)

  # ----------------
  # public functions
  # ----------------

  @doc """
  Create a new 2D bitmap with dimensions width and height.

  The image can be created from either:
  - an existing buffer
  - initialized with a background bit value (0,1)
  - predicate function that returns a boolean for each location
  - sparse set of locations with a bit value 1
  """
  @spec new(I.size(), I.size(), binary() | E.bit() | bit_predicate() | bitset()) :: %I.Bitmap{}

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

  def new(w, h, bset) when is_size(w) and is_size(h) and is_set(bset) do
    new(w, h, fn loc -> if MapSet.member?(bset, loc), do: 1, else: 0 end)
  end

  @doc """
  Create a random bitmap.

  The occupancy is a number between 0.0 and 1.0,
  which specifies the probability that each cell is alive.
  """
  @spec random(I.size(), I.size(), E.unit()) :: %I.Bitmap{}
  def random(w, h, p \\ 0.5)

  def random(w, h, 0.5) when is_size(w) and is_size(h) do
    row = Binary.padded_bits(w)
    buf = :rand.bytes(h * row)
    %I.Bitmap{width: w, height: h, row: row, buffer: buf}
  end

  def random(w, h, p) when is_size(w) and is_size(h) and is_unit(p) do
    new(w, h, fn _loc -> :rand.uniform() <= p end)
  end

  @doc "Get the extents of the bitmap."
  @spec bbox(%I.Bitmap{}) :: S.bbox2i()
  def bbox(%I.Bitmap{width: w, height: h}), do: BBox2i.from_pos_dims({0, 0}, {w, h})

  @doc "Convert to a set of locations that have bit value 1."
  @spec to_bitset(%I.Bitmap{}) :: bitset()
  def to_bitset(%I.Bitmap{} = bmp) do
    reduce(bmp, MapSet.new(), fn
      _, _, 0, bset -> bset
      i, j, 1, bset -> MapSet.put(bset, {i, j})
    end)
  end

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

  @doc """
  Count the number of bits set (1s) in a bitmap.
  """
  @spec nset(%I.Bitmap{}) :: E.count()
  def nset(%I.Bitmap{width: w, buffer: buf} = bmp) do
    case pad(bmp) do
      0 ->
        Exa.Binary.nset(buf)

      pad ->
        # ignore padding, which may be non-zero
        bmp
        |> get_rev_rows()
        |> Enum.map(&mask_bits(&1, w, pad))
        |> Enum.map(&Exa.Binary.nset/1)
        |> Enum.sum()
    end
  end

  @doc """
  Reflect the bitmap in the y-direction.

  Each row is preserved, 
  but the order of rows is reversed.
  """
  @spec reflect_y(%I.Bitmap{}) :: %I.Bitmap{}

  def reflect_y(%I.Bitmap{row: 1, buffer: buf} = bmp) do
    buf = buf |> Binary.to_bytes() |> Enum.reverse() |> Binary.from_bytes()
    %I.Bitmap{bmp | :buffer => buf}
  end

  def reflect_y(%I.Bitmap{} = bmp) do
    buf = bmp |> get_rev_rows() |> Binary.concat()
    %I.Bitmap{bmp | :buffer => buf}
  end

  @doc """
  Reflect the bitmap in the x-direction.

  Each row is reversed, but the order of rows is not changed.
  """
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

  def reflect_x(%I.Bitmap{width: w} = bmp) do
    buf =
      bmp
      |> get_rev_rows()
      |> Enum.reverse()
      |> Enum.map(&mask_reverse_bits(&1, w, pad(bmp)))
      |> Binary.concat()

    %I.Bitmap{bmp | :buffer => buf}
  end

  # mask a row buffer to remove padding 
  # return the ragged bitstring
  @spec mask_bits(binary(), E.bsize(), E.bsize()) :: E.bits()

  defp mask_bits(buf, _nbits, 0), do: buf

  defp mask_bits(buf, nbits, pad) when pad > 0 do
    <<data::size(nbits)-bits, _::size(pad)>> = buf
    data
  end

  # mask then reverse the significant bits in a row
  # pad the result back to byte boundary using pad
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
  @spec reduce(%I.Bitmap{}, a, bit_reducer(a)) :: a when a: var
  def reduce(%I.Bitmap{width: w, height: h, buffer: buf} = bmp, init, bitred) do
    pad = pad(bmp)

    {<<>>, out} =
      Enum.reduce(0..(h - 1), {buf, init}, fn j, {buf, out} ->
        {<<_::size(pad)-bits, rest::bits>>, out} =
          Enum.reduce(0..(w - 1), {buf, out}, fn
            i, {<<b::1, rest::bits>>, out} -> {rest, bitred.(i, j, b, out)}
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
  def to_ascii(%I.Bitmap{} = bmp, fg \\ ?X, bg \\ ?.) when is_char(fg) and is_char(bg) do
    out =
      reduce(bmp, <<>>, fn
        0, j, 0, out when j > 0 -> <<out::binary, ?\n, bg>>
        0, j, 1, out when j > 0 -> <<out::binary, ?\n, fg>>
        _, _, 0, out -> <<out::binary, bg>>
        _, _, 1, out -> <<out::binary, fg>>
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
      reduce(bmp, <<>>, fn
        _i, _j, 0, out -> Colorb.append_bin(pix, out, bg)
        _i, _j, 1, out -> Colorb.append_bin(pix, out, fg)
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

  # get the number of pad bits
  @spec pad(%I.Bitmap{}) :: 0..7
  defp pad(%I.Bitmap{width: w, row: row}), do: 8 * row - w

  # {byte, bit} offset address (prefix length) of a position in the buffer
  @spec addr(%I.Bitmap{}, S.pos2i()) :: {nbyte :: E.index0(), nbit :: E.index0()}
  defp addr(%I.Bitmap{row: row}, {i, j}), do: {j * row + Binary.div8(i), Binary.rem8(i)}
end

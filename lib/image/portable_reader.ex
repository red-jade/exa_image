defmodule Exa.Image.PortableReader do
  @moduledoc """
  Utilities to parse PBM/PGM/PPM files:
  portable bitmap, portable gray map and portable pixmap.
  """
  require Logger
  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Convert
  alias Exa.Math

  alias Exa.Image.Bitmap
  alias Exa.Image.Types, as: I

  @doc """
  Read a PBM/PGM/PBM file.
  """
  @spec from_file(String.t()) :: %I.Image{}
  def from_file(filename) when is_nonempty_string(filename) do
    filename |> Exa.File.from_file_binary() |> parse()
  end

  # ------
  # parser 
  # ------

  # A Portable image file has an ASCII header.
  # The file starts with a magic number.
  #
  # The magic number decides the pixel format
  # (1-bit mask, 1-byte grayscale, 3-byte rgb)
  # and the data format (ascii decimal, binary):
  # - P1 bitmap mask: bits as ascii integers (0,1) in rows padded to byte boundaries
  # - P2 byte grayscale: ascii decimal bytes, up to declared maximum value
  # - P3 rgb bytes: 3-bytes in ascii decimal format
  # - P4 bitmap mask: binary bits in rows padded to byte boundary
  # - P5 byte grayscale: binary bytes, up to declared maximum value
  # - P6 rgb bytes: binary 3-byte groups
  # 
  # The header has width and height dimensions,
  # and optional maximum byte value 
  # (if appropriate, say for grayscale).
  #
  # There are comments beginning with '#'.
  # Any amount of ASCII whitespace is a separator.

  @spec parse(binary()) :: %I.Image{}
  defp parse("P1" <> rest), do: pbm_txt(rest)
  defp parse("P2" <> rest), do: pgm_txt(rest)
  defp parse("P3" <> rest), do: ppm_txt(rest)
  defp parse("P4" <> rest), do: pbm_bin(rest)
  defp parse("P5" <> rest), do: pgm_bin(rest)
  defp parse("P6" <> rest), do: ppm_bin(rest)

  defp pbm_txt(rest) do
    {{w, h}, rest} = get_wh(rest)
    buf = bitbuf(rest, <<>>, <<>>)
    Bitmap.new(w, h, buf)
  end

  defp pbm_bin(rest) do
    {{w, h}, rest} = get_wh(rest)
    # assume the rest of the file is in padded-row binary format?
    Bitmap.new(w, h, rest)
  end

  defp pgm_txt(rest) do
    {{w, h}, rest} = get_wh(rest)
    {imax, rest} = get_imax(rest)
    buf = buf(rest, <<>>, <<>>, imax)
    Exa.Image.Image.new(w, h, :gray, buf)
  end

  defp pgm_bin(rest) do
    {{w, h}, rest} = get_wh(rest)
    {imax, rest} = get_imax(rest)
    buf = if imax == 255, do: rest, else: rescale(rest, <<>>, imax)
    Exa.Image.Image.new(w, h, :gray, buf)
  end

  defp ppm_txt(rest) do
    {{w, h}, rest} = get_wh(rest)
    {imax, rest} = get_imax(rest)
    buf = buf(rest, <<>>, <<>>, imax)
    Exa.Image.Image.new(w, h, :rgb, buf)
  end

  defp ppm_bin(rest) do
    {{w, h}, rest} = get_wh(rest)
    {imax, buf} = get_imax(rest)

    if imax != 255 do
      msg = "PPM expected 8-bits per component, found max val #{imax}"
      Logger.error(msg)
      raise RuntimeError, message: msg
    end

    Exa.Image.Image.new(w, h, :rgb, buf)
  end

  @spec get_wh(binary()) :: {{I.size(), I.size()}, binary()}
  defp get_wh(rest) do
    {w, rest} = lex(rest)
    {h, rest} = lex(rest)
    {{w, h}, rest}
  end

  @spec get_imax(binary()) :: {I.size(), binary()}
  defp get_imax(rest) do
    {imax, rest} = lex(rest)
    {maxval(imax), rest}
  end

  @spec lex(binary()) :: {non_neg_integer(), binary()}
  defp lex(<<c, rest::binary>>) when is_ws(c), do: lex(rest)
  defp lex(<<?#, rest::binary>>), do: comment(rest)
  defp lex(<<c, rest::binary>>) when is_digit(c), do: int(rest, <<c>>)

  @spec comment(binary()) :: {non_neg_integer(), binary()}
  defp comment(<<?\n, rest::binary>>), do: lex(rest)
  defp comment(<<_, rest::binary>>), do: comment(rest)

  @spec int(binary(), binary()) :: {non_neg_integer(), binary()}
  defp int(<<c, rest::binary>>, d) when is_digit(c), do: int(rest, <<d::binary, c>>)
  defp int(<<c, rest::binary>>, d) when is_ws(c), do: {Convert.d2i(d), rest}

  # read a whitespace-separated ascii bit buffer 
  @spec bitbuf(binary(), E.bits(), binary()) :: binary()
  defp bitbuf(<<?0, rest::binary>>, row, out), do: bitbuf(rest, <<row::bits, 0::1>>, out)
  defp bitbuf(<<?1, rest::binary>>, row, out), do: bitbuf(rest, <<row::bits, 1::1>>, out)
  defp bitbuf(<<?\n, rest::binary>>, row, out), do: bitbuf(rest, <<>>, add(out, row))
  defp bitbuf(<<c, rest::binary>>, row, out) when is_ws(c), do: bitbuf(rest, row, out)
  defp bitbuf(<<>>, <<>>, out), do: out
  defp bitbuf(<<>>, row, out), do: add(out, row)

  # append bits to bytes
  @spec add(binary(), E.bits()) :: binary()
  defp add(bytes, bits) do
    case rem(bit_size(bits), 8) do
      0 -> <<bytes::binary, bits::binary>>
      pad -> <<bytes::binary, bits::bits, 0::pad*1>>
    end
  end

  # read a whitespace-separated ascii decimal integer buffer 
  @spec buf(binary(), binary(), binary(), non_neg_integer()) :: binary()

  defp buf(<<>>, <<>>, out, _imax), do: out

  defp buf(<<>>, d, out, imax) do
    <<out::binary, to_int(d, imax)>>
  end

  defp buf(<<c, rest::binary>>, d, out, imax) when is_digit(c) do
    buf(rest, <<d::binary, c>>, out, imax)
  end

  defp buf(<<c, rest::binary>>, <<>>, out, imax) when is_ws(c) do
    buf(rest, <<>>, out, imax)
  end

  defp buf(<<c, rest::binary>>, d, out, imax) when is_ws(c) do
    buf(rest, <<>>, <<out::binary, to_int(d, imax)>>, imax)
  end

  # rescale a binary byte buffer - byte value 1..254
  @spec rescale(binary(), binary(), byte()) :: binary()

  defp rescale(<<>>, out, _imax), do: out

  defp rescale(<<i, rest::binary>>, out, imax) when i >= imax do
    rescale(rest, <<out::binary, imax>>, imax)
  end

  defp rescale(<<i, rest::binary>>, out, imax) do
    rescale(rest, <<out::binary, Convert.f2b(i / imax)>>, imax)
  end

  # convert a decimal integer string to a clamped and/or scaled byte value
  @spec to_int(binary(), non_neg_integer()) :: byte()

  defp to_int(d, 255) do
    d |> Convert.d2i() |> Math.byte()
  end

  defp to_int(d, imax) do
    i = Math.clamp_(0, Convert.d2i(d), imax)
    Convert.f2b(i / imax)
  end

  # some files seem to think that max size should be power of 2
  # but when we divide, we want the actual max value of that type
  @spec maxval(non_neg_integer()) :: non_neg_integer()
  defp maxval(256), do: 255
  defp maxval(128), do: 127
  defp maxval(64), do: 63
  defp maxval(32), do: 31
  defp maxval(16), do: 15
  defp maxval(imax), do: imax
end

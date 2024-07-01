defmodule Exa.Image.Resize do
  @moduledoc "Utilities for resizing image buffers."

  require Logger
  use Exa.Image.Constants

  alias Exa.Math

  alias Exa.Image.Types, as: I

  alias Exa.Image.Image

  # ----------------
  # public functions
  # ----------------

  @doc """
  Downsize, upsize and resize.

  Downsize is a negative integer.
  The image will be reduced by skipping pixels (x) and rows (y)
  and copying individual pixels to the output.
  There is no interpolation.
  Every output pixel is a copy of a pixel in the input.
  Thre may be remainder pixels and rows.
  The last pixels in an input row may be ignored in the output.
  The last rows in the input may be ignored in the output. 
  Downsize of -1 is the identity function.

  Upsize is a positive integer.
  The image will be expanded by duplicating 
  individual pixels from the input to the output.
  There is no interpolation.
  Every output pixel is a copy of a pixel in the input.
  Every input pixel is represented in the output.
  Upsize of 1 is the identity function.

  Resize is a positive float.
  Values `[0.0,1.0]` will shrink the image.
  Values above 1.0 will expand the image.
  Resize of 1.0 is the identity function.
  Negative float factors are not valid.
  """
  @spec resize(%I.Image{}, number()) :: %I.Image{}
  def resize(%I.Image{} = img, fac) when is_number(fac) do
    case Math.snapi(fac) do
      x when x == 0 ->
        msg = "Factor is zero: #{fac}"
        Logger.error(msg)
        raise ArgumentError, message: msg

      x when x == 1 ->
        img

      x when x == -1 ->
        img

      ifac when is_integer(ifac) and ifac < -1 ->
        do_downsize(img, -ifac)

      ifac when is_integer(ifac) and ifac > 1 ->
        do_upsize(img, ifac)

      xfac when is_float(xfac) and xfac > 0.0 ->
        do_resize(img, xfac)

      xfac when is_float(xfac) and xfac < 0.0 ->
        msg = "Float factor is -ve: #{fac}"
        Logger.error(msg)
        raise ArgumentError, message: "Float factor is -ve: #{fac}"
    end
  end

  # downsize

  defp do_downsize(%I.Image{width: w, height: h, ncomp: ncomp} = img, ifac) do
    buf =
      img
      |> Image.get_rows(ifac)
      |> Enum.reduce(<<>>, fn row, buf ->
        new_row = do_down_row(row, ncomp * (ifac - 1) * 8, ncomp * 8, <<>>)
        <<buf::binary, new_row::binary>>
      end)

    new_w = div(w, ifac)
    %I.Image{img | width: new_w, height: div(h, ifac), row: new_w * ncomp, buffer: buf}
  end

  defp do_down_row(<<>>, _skip, _ncomp, buf), do: buf

  defp do_down_row(row, skip, ncomp8, buf) do
    <<pix::ncomp8*1, _::skip*1, rest::binary>> = row
    do_down_row(rest, skip, ncomp8, <<buf::binary, pix::ncomp8*1>>)
  end

  # upsize 

  defp do_upsize(%I.Image{width: w, height: h, ncomp: ncomp, row: imgrow} = img, ifac) do
    buf =
      img
      |> Image.get_rows()
      |> Enum.reduce(<<>>, fn row, buf ->
        new_row = do_up_row(row, ifac, ncomp * 8, <<>>)
        Enum.reduce(1..ifac, buf, fn _, buf -> <<buf::binary, new_row::binary>> end)
      end)

    %I.Image{img | width: ifac * w, height: ifac * h, row: ifac * imgrow, buffer: buf}
  end

  defp do_up_row(<<>>, _ifac, _ncomp, buf), do: buf

  defp do_up_row(row, ifac, ncomp8, buf) do
    <<pix::ncomp8*1, rest::binary>> = row
    new_buf = Enum.reduce(1..ifac, buf, fn _, buf -> <<buf::binary, pix::ncomp8*1>> end)
    do_up_row(rest, ifac, ncomp8, new_buf)
  end

  # resize

  defp do_resize(_img, xfac) when xfac > 0.0 and xfac != 0.0 and xfac != 1.0 do
    raise RuntimeError, message: "Not implemented"
  end
end

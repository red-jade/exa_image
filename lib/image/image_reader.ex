defmodule Exa.Image.ImageReader do
  @moduledoc """
  Read BMP/TGA/TIF/PNG and PBM/PGM/PPM images.
  Simple wrappers around the Wings3D E3D image utilities
  and the Exa portable reader.
  """
  require Logger
  use Exa.Image.Constants

  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Color.Types, as: C
  alias Exa.Image.Types, as: I
  alias Exa.Image.PortableReader

  @doc """
  Read an image file.
  Use the filetype to determine the type.
  """
  @spec from_file(String.t()) :: %I.Image{}
  def from_file(filename) when is_nonempty_string(filename) do
    {_dir, name, [_ | _] = types} = Exa.File.split(filename)
    type = List.last(types)

    cond do
      type in @e3d_filetypes ->
        Logger.info("Read #{String.upcase(type)} image file '#{name}.#{type}'")

        filename
        |> String.to_charlist()
        |> :e3d_image.load()
        |> e3d_to_exa()

      type in @exa_filetypes ->
        PortableReader.from_file(filename)

      true ->
        msg = "Unsupported filetype, expecting '#{@filetypes}', found '#{type}'"
        Logger.error(msg)
        raise ArgumentError, message: msg
    end
  end

  # -----------------
  # private functions
  # -----------------

  # -record(e3d_image,     %% Currently supported formats:
  #   {type = r8g8b8,      %% [g8 (gray8), a8 (alpha8) (Ch:Size)+[s|f]=signed|float]
  #                        %%   ex: r32g32b32s (rgb with 32 (signed) bits per channel)
  #    bytes_pp = 3,       %% bytes per pixel
  #    alignment = 1,      %% A = 1|2|4 Next row starts direct|even 2|even 4
  #    order = lower_left, %% First pixel is in:
  #                        %% lower_left,lower_right,upper_left,upper_right]
  #    width = 0,          %% in pixels
  #    height = 0,         %% in pixels
  #    image,              %% binary
  #    filename=none,      %% Filename or none
  #    name=[],            %% Name of image
  #    extra=[]            %% mipmaps, cubemaps, filter ...
  #   }).

  # convert E3D image to Exa
  @spec e3d_to_exa(tuple()) :: %I.Image{}
  defp e3d_to_exa({:e3d_image, type, bpp, align, order, w, h, buf, _, _, _}) do
    pix = pixel(type, bpp)
    1 = align(align)
    :upper_left = order(order)
    Exa.Image.Image.new(w, h, pix, buf)
  end

  # convert pixel format and validate bytes-per-pixel
  @spec pixel(atom(), I.size()) :: C.pixel()
  defp pixel(:r8g8b8, 3), do: :rgb
  defp pixel(:r8g8b8a8, 4), do: :rgba

  defp pixel(e3d_pix, bpp) do
    msg = "Cannot load image, expecting RGB 3 bpp, found #{e3d_pix} #{bpp} bpp"
    Logger.error(msg)
    raise RuntimeError, message: msg
  end

  # validate alignment, always 1
  @spec align(E.count1()) :: E.count1()

  defp align(1), do: 1

  defp align(e3d_align) do
    msg = "Cannot load image, expecting 1-byte aligned, found #{e3d_align}"
    Logger.error(msg)
    raise RuntimeError, message: msg
  end

  # validate data ordering, always upper-left
  @spec order(atom()) :: atom()

  defp order(:upper_left), do: :upper_left

  defp order(e3d_ord) do
    raise RuntimeError,
      message: "Cannot load image, expecting upper-left order, found #{e3d_ord}"
  end
end

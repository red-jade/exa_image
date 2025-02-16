defmodule Exa.Image.ImageWriter do
  @moduledoc """
  Write BMP/TGA/TIF/PNG images (and PGM/PPM in future).
  Simple wrappers around the Wings3D E3D image utilities
  and the Exa portable writer.
  """
  require Logger
  use Exa.Image.Constants

  import Exa.Types

  alias Exa.File

  alias Exa.Color.Types, as: C
  alias Exa.Image.Types, as: I

  @doc """
  Write an image file.
  Use the filetype to determine the format.

  Raises an error if the format is unsupported, 
  or there is any failure.
  """
  @spec to_file(%I.Image{}, String.t()) :: :ok
  def to_file(img, filename) when is_string_nonempty(filename) do
    {dir, name, types} = Exa.File.split(filename)
    File.ensure_dir!(dir)
    type = List.last(types)

    cond do
      type in @e3d_filetypes ->
        Logger.info("Writing #{String.upcase(type)} image file '#{name}.#{type}'")

        charlist = String.to_charlist(filename)

        case img |> exa_to_e3d(filename) |> :e3d_image.save(charlist) do
          :ok ->
            :ok

          {:error, reason} ->
            msg = "E3D error '#{reason}'"
            Logger.error(msg)
            raise RuntimeError, message: msg
        end

      type in @exa_filetypes ->
        # PortableWriter.to_portable(img, dir, name, type)
        msg = "Unsupported filetype, portable format '#{type}'"
        Logger.error(msg)
        raise ArgumentError, msg

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
  @spec exa_to_e3d(%I.Image{}, String.t()) :: tuple()
  defp exa_to_e3d(%I.Image{width: w, height: h, pixel: pix, buffer: buf}, filename) do
    align = 1
    order = :upper_left
    {type, bpp} = pixel(pix)
    {:e3d_image, type, bpp, align, order, w, h, buf, filename, [], []}
  end

  # convert pixel format and validate bytes-per-pixel
  @spec pixel(C.pixel()) :: {atom(), I.size()}
  defp pixel(:rgb), do: {:r8g8b8, 3}
  defp pixel(:gray), do: {:g8, 1}
end

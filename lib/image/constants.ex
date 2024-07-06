defmodule Exa.Image.Constants do
  @moduledoc "Constants for image formats."

  defmacro __using__(_) do
    quote do
      @filetype_png "png"
      @filetype_tga "tga"
      @filetype_bmp "bmp"
      @filetype_tif "tif"

      @filetype_ppm "ppm"
      @filetype_pgm "pgm"
      @filetype_pbm "pbm"

      @filetype_mp4 "mp4"
      @filetype_avi "avi"

      @e3d_filetypes [@filetype_tga, @filetype_bmp, @filetype_png, @filetype_tif, "tiff"]

      @exa_filetypes [@filetype_pbm, @filetype_pgm, @filetype_ppm]

      @filetypes @e3d_filetypes ++ @exa_filetypes
    end
  end
end

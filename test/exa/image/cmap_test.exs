defmodule Exa.Image.CmapTest do
  use ExUnit.Case

  use Exa.Image.Constants

  import Exa.Image.Image

  alias Exa.Image.ImageWriter
  alias Exa.Color.Colormap3b

  @png_out_dir ["test", "output", "image", "png"]

  defp png(name), do: Exa.File.join(@png_out_dir, name, @filetype_png)

  test "colormap to image" do
    Colormap3b.dark_red() |> from_colormap(2, 100) |> ImageWriter.to_file(png("dred_cmap"))
    Colormap3b.sat_magenta() |> from_colormap(2, 100) |> ImageWriter.to_file(png("smag_cmap"))
    Colormap3b.blue_white_red() |> from_colormap(2, 100) |> ImageWriter.to_file(png("bwr_cmap"))
  end
end

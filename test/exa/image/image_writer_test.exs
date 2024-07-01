defmodule Exa.Image.ImageWriterTest do
  use ExUnit.Case

  use Exa.Image.Constants

  import Exa.Image.ImageReader
  import Exa.Image.ImageWriter

  alias Exa.Image.Image
  alias Exa.Image.Resize

  @ppm_in_dir ["test", "input", "image", "ppm"]

  @png_out_dir ["test", "output", "image", "png"]

  defp in_ppm(name), do: Exa.File.join(@ppm_in_dir, name, @filetype_ppm)
  defp out_png(name), do: Exa.File.join(@png_out_dir, name, @filetype_png)

  @rgbp Image.new(2, 2, :rgb, <<255, 0, 0, 0, 255, 0, 0, 0, 255, 205, 133, 63>>)

  # PNG -----------

  test "png simple" do
    img = Resize.resize(@rgbp, 16)
    to_file(img, out_png("test_card"))
  end

  test "read write" do
    mandrill = from_file(in_ppm("mandrill256"))
    to_file(mandrill, out_png("mandrill256"))
  end
end

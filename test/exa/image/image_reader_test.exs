defmodule Exa.Image.ImageReaderTest do
  use ExUnit.Case

  use Exa.Image.Constants
  alias Exa.Image.Types, as: I

  import Exa.Image.ImageReader

  @png_dir ["test", "input", "image", "png"]

  @mah_jong "mah_jong"
  @dice "dice_trans"

  defp file(name), do: Exa.File.join(@png_dir, name, @filetype_png)

  # PNG -----------

  test "png simple" do
    img = from_file(file(@mah_jong))
    assert %I.Image{pixel: :rgb, ncomp: 3, width: 27, height: 39} = img
  end

  test "png transparent" do
    img = from_file(file(@dice))
    assert %I.Image{pixel: :rgba, ncomp: 4, width: 120, height: 90} = img
  end
end

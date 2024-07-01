defmodule Exa.Image.PortableReaderTest do
  use ExUnit.Case

  use Exa.Image.Constants

  import Exa.Image.PortableReader

  alias Exa.Image.Types, as: I

  @in_dir ["test", "input", "image", "ppm"]

  @pbm_simple_txt "simple_txt"

  @pgm_simple_txt "simple_txt"
  @pgm_scale_txt "scale_txt"
  @pgm_monalisa_bin "monalisa256"

  @ppm_simple_txt "simple_txt"
  @ppm_mandrill_bin "mandrill256"

  defp pbm(name), do: Exa.File.join(@in_dir, name, @filetype_pbm)
  defp pgm(name), do: Exa.File.join(@in_dir, name, @filetype_pgm)
  defp ppm(name), do: Exa.File.join(@in_dir, name, @filetype_ppm)

  # PBM -----------

  test "pbm simple ascii" do
    bmp = from_file(pbm(@pbm_simple_txt))
    assert %I.Bitmap{width: 4, height: 4, row: 1, buffer: <<160, 80, 160, 80>>} = bmp
  end

  # PGM -----------

  test "pgm simple ascii" do
    img = from_file(pgm(@pgm_simple_txt))

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :gray,
             ncomp: 1,
             row: 4,
             buffer: <<1, 2, 3, 4, 11, 12, 13, 14, 21, 22, 23, 24, 31, 32, 33, 34>>
           } = img
  end

  test "pgm rescale ascii" do
    img = from_file(pgm(@pgm_scale_txt))

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :gray,
             ncomp: 1,
             row: 4,
             buffer: <<17, 34, 51, 68, 85, 102, 119, 136, 204, 221, 238, 255, 255, 255, 255, 255>>
           } = img
  end

  test "pgm monalisa" do
    img = from_file(pgm(@pgm_monalisa_bin))
    assert %I.Image{width: 256, height: 256, pixel: :gray, ncomp: 1} = img
  end

  # PPM ----------

  test "ppm simple ascii" do
    img = from_file(ppm(@ppm_simple_txt))

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<255, 0, 0, 0, 255, 0, 0, 0, 255, 205, 133, 63>>
           } = img
  end

  test "ppm mandrill" do
    img = from_file(ppm(@ppm_mandrill_bin))
    assert %I.Image{width: 256, height: 256, pixel: :rgb, ncomp: 3} = img
  end
end

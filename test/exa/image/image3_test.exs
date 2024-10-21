defmodule Exa.Image.Image3Test do
  use ExUnit.Case

  use Exa.Image.Constants
  import Exa.Image.Image

  alias Exa.Image.Types, as: I

  alias Exa.Std.Histo1D
  alias Exa.Std.Histo2D

  alias Exa.Space.BBox2i
  alias Exa.Color.Col3b
  alias Exa.Color.Col3f
  alias Exa.Color.Col3name
  alias Exa.Color.Colormap3b

  alias Exa.Image.Resize
  alias Exa.Image.Convolve
  alias Exa.Image.ImageWriter
  alias Exa.Image.Bitmap

  @bench_dir "test/bench"

  @red Col3b.red()
  @green Col3b.green()
  @blue Col3b.blue()
  @peru "peru" |> Col3name.new() |> Col3name.to_col3b()

  @in_png_dir ["test", "input", "image", "png"]
  @out_png_dir ["test", "output", "image", "png"]

  @in_ppm_dir ["test", "input", "image", "ppm"]

  @mah_jong "mah_jong"
  @mandrill "mandrill256"
  @dice "dice_trans"

  @mandice "mandice"

  defp in_png(name), do: Exa.File.join(@in_png_dir, name, @filetype_png)
  defp out_png(name), do: Exa.File.join(@out_png_dir, name, @filetype_png)

  defp in_ppm(name), do: Exa.File.join(@in_ppm_dir, name, @filetype_ppm)

  @cmap Colormap3b.new([
          Col3f.black(),
          Col3f.gray(),
          Col3f.white(),
          Col3f.red(),
          Col3f.green(),
          Col3f.blue(),
          Col3f.cyan(),
          Col3f.magenta(),
          Col3f.yellow()
        ])

  # build an image in RGB format
  # but pixels are grayscale (all components equal)
  # with values in ascending order
  defp counting_gray(w, h) do
    buf =
      Enum.reduce(0..(h - 1), <<>>, fn j, buf ->
        Enum.reduce(0..(w - 1), buf, fn i, buf ->
          gray = rem(i + 10 * j, 256)
          Col3b.append_bin(buf, Col3b.gray(gray))
        end)
      end)

    new(w, h, :rgb, buf)
  end

  # build an alternating chequerboard image in RGB format
  # pixels are just black and white
  defp chess_bw(w, h) do
    buf =
      Enum.reduce(0..(h - 1), <<>>, fn j, buf ->
        Enum.reduce(0..(w - 1), buf, fn i, buf ->
          bw = if rem(i + j, 2) == 0, do: 0, else: 255
          Col3b.append_bin(buf, Col3b.gray(bw))
        end)
      end)

    new(w, h, :rgb, buf)
  end

  # {0}  01010000  0x50  60
  # {1}  10100000  0xA0 160
  # {2}  01010000  0x50  60
  # {3}  10100000  0xA0 160
  @chess_bit44 <<0::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1, 0::1, 0::1,
                 0::1, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1, 0::1,
                 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>

  # note kernel is rotated - vectors are y-column vectors
  # can't tell if it is x-y symmetric  transpose
  @blur_kernel3 {
    {0.05, 0.05, 0.05},
    {0.05, 0.60, 0.05},
    {0.05, 0.05, 0.05}
  }

  @blur_kernel5 {
    {0.01, 0.02, 0.04, 0.02, 0.01},
    {0.02, 0.04, 0.08, 0.04, 0.02},
    {0.04, 0.08, 0.16, 0.08, 0.04},
    {0.02, 0.04, 0.08, 0.04, 0.02},
    {0.01, 0.02, 0.04, 0.02, 0.01}
  }

  # red green / blue peru
  @rgbp new(2, 2, :rgb, <<255, 0, 0, 0, 255, 0, 0, 0, 255, 205, 133, 63>>)

  test "simple" do
    rbuf = <<255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0>>
    gbuf = <<0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255>>
    pbuf = <<205, 133, 63, 205, 133, 63, 205, 133, 63, 205, 133, 63>>

    rimg = new(2, 2, :rgb, @red)
    assert %I.Image{width: 2, height: 2, pixel: :rgb, ncomp: 3, row: 6, buffer: rbuf} == rimg

    gimg = new(2, 2, :rgb, gbuf)
    assert %I.Image{width: 2, height: 2, pixel: :rgb, ncomp: 3, row: 6, buffer: gbuf} == gimg

    pimg = new(2, 2, :rgb, pbuf)
    assert %I.Image{width: 2, height: 2, pixel: :rgb, ncomp: 3, row: 6, buffer: pbuf} == pimg
  end

  test "get set pixel" do
    img = @rgbp
    assert @red == get_pixel(img, {0, 0})
    assert @green == get_pixel(img, {1, 0})
    assert @blue == get_pixel(img, {0, 1})
    assert @peru == get_pixel(img, {1, 1})

    assert_raise ArgumentError, fn -> get_pixel(img, {0, 10}) end

    # write peru into the green pixel
    new_img = set_pixel(img, {1, 0}, @peru)
    assert @red == get_pixel(new_img, {0, 0})
    assert @peru == get_pixel(new_img, {1, 0})
    assert @blue == get_pixel(new_img, {0, 1})
    assert @peru == get_pixel(new_img, {1, 1})
  end

  test "get set subimage" do
    img = counting_gray(5, 5)
    {:ok, sub} = get_subimage!(img, {2, 1}, {2, 3})

    assert %I.Image{
             width: 2,
             height: 3,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<12, 12, 12, 13, 13, 13, 22, 22, 22, 23, 23, 23, 32, 32, 32, 33, 33, 33>>
           } == sub

    assert :error == get_subimage!(img, {2, 1}, {7, 3})

    red = new(2, 3, :rgb, @red)
    {:ok, new_img} = set_subimage!(img, {2, 1}, red)

    assert %I.Image{
             width: 5,
             height: 5,
             pixel: :rgb,
             ncomp: 3,
             row: 15,
             buffer:
               <<0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 10, 10, 10, 11, 11, 11, 255, 0, 0,
                 255, 0, 0, 14, 14, 14, 20, 20, 20, 21, 21, 21, 255, 0, 0, 255, 0, 0, 24, 24, 24,
                 30, 30, 30, 31, 31, 31, 255, 0, 0, 255, 0, 0, 34, 34, 34, 40, 40, 40, 41, 41, 41,
                 42, 42, 42, 43, 43, 43, 44, 44, 44>>
           } = new_img
  end

  test "rotate reflect" do
    rgbp = @rgbp

    reflect_x = %I.Image{rgbp | :buffer => <<0, 255, 0, 255, 0, 0, 205, 133, 63, 0, 0, 255>>}
    assert reflect_x == reflect_x(rgbp)

    reflect_y = %I.Image{rgbp | :buffer => <<0, 0, 255, 205, 133, 63, 255, 0, 0, 0, 255, 0>>}
    assert reflect_y == reflect_y(rgbp)

    rotate_180 = %I.Image{rgbp | :buffer => <<205, 133, 63, 0, 0, 255, 0, 255, 0, 255, 0, 0>>}
    assert rotate_180 == rotate_180(rgbp)

    rotate_90 = %I.Image{rgbp | :buffer => <<0, 0, 255, 255, 0, 0, 205, 133, 63, 0, 255, 0>>}
    assert rotate_90 == rotate_90(rgbp)

    rotate_270 = %I.Image{rgbp | :buffer => <<0, 255, 0, 205, 133, 63, 255, 0, 0, 0, 0, 255>>}
    assert rotate_270 == rotate_270(rgbp)
  end

  test "pixels" do
    rgbp = @rgbp
    assert [{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {205, 133, 63}] = get_pixels(rgbp)
  end

  test "map pixels" do
    rgbp = @rgbp

    # grayscale
    gray = map_pixels(rgbp, &Col3b.to_gray/1)

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<76, 76, 76, 150, 150, 150, 29, 29, 29, 147, 147, 147>>
           } = gray

    # darken, lighten
    dark = map_pixels(rgbp, &Col3b.dark/1)

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<128, 0, 0, 0, 128, 0, 0, 0, 128, 103, 67, 32>>
           } = dark

    pale = map_pixels(rgbp, &Col3b.pale/1)

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<255, 128, 128, 128, 255, 128, 128, 128, 255, 230, 194, 159>>
           } = pale
  end

  test "parallel map pixels" do
    mandrill = @mandrill |> in_ppm() |> from_file()

    gray = map_pixels(mandrill, &Col3b.to_gray/1)
    ImageWriter.to_file(gray, out_png("mandrill_gray"))

    {:ok, pgray} = pmap_pixels(mandrill, &Col3b.to_gray/1)
    ImageWriter.to_file(pgray, out_png("mandrill_pgray"))

    assert gray == pgray
  end

  test "reduce histogram" do
    # @rgbp new(2, 2, :rgb, <<255, 0, 0, 0, 255, 0, 0, 0, 255, 205, 133, 63>>)
    img = @rgbp

    rhisto = histogram(img, :r)
    rsparse = Histo1D.to_sparse_list(rhisto)
    assert [{0, 2}, {205, 1}, {255, 1}] == rsparse

    ghisto = histogram(img, :g)
    gsparse = Histo1D.to_sparse_list(ghisto)
    assert [{0, 2}, {133, 1}, {255, 1}] == gsparse

    bhisto = histogram(img, :b)
    bsparse = Histo1D.to_sparse_list(bhisto)
    assert [{0, 2}, {63, 1}, {255, 1}] == bsparse

    mah = from_file(in_png(@mah_jong))
    mahisto = histogram(mah, :b)
    _masparse = Histo1D.to_sparse_list(mahisto)
    assert 124 == Histo1D.get(mahisto, 0)
  end

  test "colormap" do
    Colormap3b.dark_red()
    |> from_cmap(2, 100)
    |> ImageWriter.to_file(out_png("dred_cmap"))

    Colormap3b.sat_magenta()
    |> from_cmap(2, 100)
    |> ImageWriter.to_file(out_png("smag_cmap"))

    Colormap3b.blue_white_red()
    |> from_cmap(2, 100)
    |> ImageWriter.to_file(out_png("bwr_cmap"))
  end

  test "index and colormap" do
    iximg = new(3, 3, :index, <<0, 1, 2, 3, 4, 5, 6, 7, 8>>)

    assert {:colormap, :index, :rgb,
            %{
              0 => {0, 0, 0},
              1 => {128, 128, 128},
              2 => {255, 255, 255},
              3 => {255, 0, 0},
              4 => {0, 255, 0},
              5 => {0, 0, 255},
              6 => {0, 255, 255},
              7 => {255, 0, 255},
              8 => {255, 255, 0}
            }} = @cmap

    rgb = apply_cmap(iximg, @cmap)

    assert %I.Image{
             width: 3,
             height: 3,
             pixel: :rgb,
             ncomp: 1,
             row: 3,
             buffer:
               <<0, 0, 0, 128, 128, 128, 255, 255, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 255,
                 255, 255, 0, 255, 255, 255, 0>>
           } = rgb
  end

  test "histogram" do
    # build histo with diagonal ramp populated
    Enum.reduce(1..20, Histo2D.new(), fn i, h ->
      Enum.reduce(1..i, h, fn _k, h -> Histo2D.inc(h, {i, i}) end)
    end)
    |> from_histo2d()
    |> apply_cmap(Colormap3b.dark_red())
    |> Resize.resize(8)
    |> ImageWriter.to_file(out_png("diag_histo"))
  end

  test "bitmap alpha" do
    bmp = Bitmap.new(4, 4, @chess_bit44)
    img = chess_bw(4, 4)
    out = bitmap_alpha(bmp, img, :rgba)

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :rgba,
             ncomp: 4,
             row: 16,
             buffer:
               <<0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255,
                 255, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255,
                 0, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 255, 255, 255,
                 255, 0, 0, 0, 0>>
           } = out
  end

  test "bitmap matte" do
    bmp = Bitmap.new(4, 4, @chess_bit44)
    img1 = new(4, 4, :rgb, {255, 0, 0})
    img2 = new(4, 4, :rgb, {0, 0, 255})
    out = matte(bmp, img1, img2)

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :rgb,
             ncomp: 3,
             row: 12,
             buffer:
               <<0, 0, 255, 255, 0, 0, 0, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0, 255, 255, 0, 0, 0,
                 0, 255, 0, 0, 255, 255, 0, 0, 0, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0, 255, 255, 0,
                 0, 0, 0, 255>>
           } = out
  end

  test "alpha blend" do
    mode = {:func_add, :func_add, :src_alpha, :one_minus_src_alpha, nil, :zero, :one, nil}
    dice = @dice |> in_png() |> from_file()
    clip = BBox2i.from_pos_dims({dice.width, dice.height})
    {:ok, mandrill} = @mandrill |> in_ppm() |> from_file() |> crop(clip)

    blend = alpha_blend(dice, mandrill, mode)
    to_file(blend, out_png(@mandice))
  end

  test "split merge 64" do
    img64 = counting_gray(64, 64)
    split64 = split(img64, 8 * 64 * 3)

    assert 8 = length(split64)

    Enum.each(split64, fn img ->
      assert 64 = img.width
      assert :rgb = img.pixel
      assert 3 = img.ncomp
      assert 192 = img.row
    end)

    assert 64 = Enum.reduce(split64, 0, fn img, h -> h + img.height end)
    assert 12_288 = Enum.reduce(split64, 0, fn img, sz -> sz + byte_size(img.buffer) end)

    heights = List.duplicate(8, 8)
    assert ^heights = Enum.map(split64, & &1.height)

    merge64 = merge(split64)
    assert ^img64 = merge64
  end

  test "split merge 100" do
    img100 = counting_gray(100, 100)
    split100 = split(img100, 1024)

    assert 34 = length(split100)

    Enum.each(split100, fn img ->
      assert 100 = img.width
      assert :rgb = img.pixel
      assert 3 = img.ncomp
      assert 300 = img.row
    end)

    assert 100 = Enum.reduce(split100, 0, fn img, h -> h + img.height end)
    assert 30_000 = Enum.reduce(split100, 0, fn img, sz -> sz + byte_size(img.buffer) end)

    heights = Enum.reverse([1 | List.duplicate(3, 33)])
    assert ^heights = Enum.map(split100, & &1.height)

    merge100 = merge(split100)
    assert ^img100 = merge100
  end

  test "split merge for individual rows" do
    img5 = counting_gray(5, 5)
    [^img5] = split(img5, 1024)
  end

  test "split n" do
    img64 = counting_gray(64, 64)
    nproc = Exa.System.n_processors()

    split64 = split_n(img64)
    assert ^nproc = length(split64)
    assert ^img64 = merge(split64)

    split64 = split_n(img64, 2)
    assert 2 = length(split64)
    assert ^img64 = merge(split64)

    img100 = counting_gray(100, 100)
    split100 = split_n(img100, 10)
    assert 10 = length(split100)
    assert ^img100 = merge(split100)
  end

  test "map kernel" do
    # resize(@rgbp, 2)
    rgbp = @rgbp
    blur = Convolve.map_kernel(rgbp, @blur_kernel3)

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :rgb,
             ncomp: 3,
             row: 6,
             buffer: <<202, 32, 28, 46, 205, 19, 212, 26, 31, 179, 125, 60>>
           } = blur
  end

  test "sample" do
    rgbp = @rgbp

    # normalized and in first pixel
    assert @red = sample(rgbp, {0.1, 0.2}, true, :wrap_repeat, :interp_nearest)

    # not mormalized but still nearest to first pixel
    assert @red = sample(rgbp, {0.7, 0.9}, false, :wrap_repeat, :interp_nearest)

    # normalized and in first pixel, bilinear but within 0.5 of origin
    assert @red = sample(rgbp, {0.1, 0.2}, true, :wrap_repeat, :interp_linear)

    # not mormalized but nearest to first pixel, 
    # but away frm the corner bilinear and ~equidistant to all four pixels
    sample = sample(rgbp, {0.9999, 1.0001}, false, :wrap_repeat, :interp_linear)
    expect = Col3f.blend([@red, @green, @blue, @peru]) |> Col3f.to_col3b()
    assert expect == sample

    # TODO - line through image ...
  end

  test "upsize downsize resize" do
    img = Resize.resize(@rgbp, 2)

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :rgb,
             ncomp: 3,
             row: 12,
             buffer:
               <<255, 0, 0, 255, 0, 0, 0, 255, 0, 0, 255, 0, 255, 0, 0, 255, 0, 0, 0, 255, 0, 0,
                 255, 0, 0, 0, 255, 0, 0, 255, 205, 133, 63, 205, 133, 63, 0, 0, 255, 0, 0, 255,
                 205, 133, 63, 205, 133, 63>>
           } == img

    res = Resize.resize(img, -2)
    assert @rgbp == res
  end

  # benchmark image access and processing ----------

  @tag benchmark: true
  @tag timeout: 300_000
  test "access benchmarks" do
    Benchee.run(
      benchmarks(),
      time: 20,
      save: [path: Path.join(@bench_dir, "image.benchee")],
      load: Path.join(@bench_dir, "image.latest.benchee")
    )
  end

  @n 128

  defp benchmarks() do
    img = new(@n, @n, :rgb, @peru)
    red33 = new(3, 3, :rgb, @red)

    %{
      # access
      "get_pixel" => fn ->
        for i <- 0..(@n - 1) do
          for j <- 0..(@n - 1) do
            get_pixel(img, {i, j})
          end
        end
      end,
      "set_pixel" => fn ->
        for i <- 0..(@n - 1) do
          for j <- 0..(@n - 1) do
            set_pixel(img, {i, j}, @red)
          end
        end
      end,
      "get_subimage" => fn ->
        for i <- 0..(@n - 3) do
          for j <- 0..(@n - 3) do
            get_subimage!(img, {i, j}, {3, 3})
          end
        end
      end,
      "set_subimage" => fn ->
        for i <- 0..(@n - 3) do
          for j <- 0..(@n - 3) do
            set_subimage!(img, {i, j}, red33)
          end
        end
      end,

      # process
      "upsize" => fn -> Resize.resize(img, 2) end,
      "downsize" => fn -> Resize.resize(img, -2) end,
      "sample nearest" => fn ->
        for i <- 0..(@n - 1) do
          for j <- 0..(@n - 1) do
            sample(img, {i + 0.1, j + 0.7}, false, :wrap_repeat, :interp_nearest)
          end
        end
      end,
      "sample bilinear" => fn ->
        for i <- 0..(@n - 1) do
          for j <- 0..(@n - 1) do
            sample(img, {i + 0.1, j + 0.7}, false, :wrap_repeat, :interp_linear)
          end
        end
      end,
      "map_pixels" => fn ->
        map_pixels(img, &Col3b.to_gray(&1))
      end,
      "map_kernel3" => fn ->
        Convolve.map_kernel(img, @blur_kernel3)
      end,
      "map_kernel5" => fn ->
        Convolve.map_kernel(img, @blur_kernel5)
      end
    }
  end

  # benchmark parallel processing ----------

  @tag benchmark: true
  @tag timeout: 400_000
  test "parallel pixel processing benchmarks" do
    Benchee.run(
      para_benchmarks(),
      time: 20,
      save: [path: Path.join(@bench_dir, "image_parallel.benchee")],
      load: Path.join(@bench_dir, "image_parallel.latest.benchee")
    )
  end

  @n_para 512

  defp para_benchmarks() do
    img = new(@n_para, @n_para, :rgb, @peru)
    gfun = &Col3b.to_gray(&1)
    bmap = %{"map pixels scalar" => fn -> pmap_pixels(img, gfun) end}

    Enum.reduce(1..16, bmap, fn n, bmap ->
      Map.put(bmap, "map pixels para #{n}", fn -> pmap_pixels(img, gfun, n) end)
    end)
  end
end

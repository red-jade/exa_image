defmodule Exa.Image.Image1Test do
  use ExUnit.Case
  use Exa.Image.Constants

  import Exa.Image.Image
  import Exa.Image.Resize
  alias Exa.Image.Types, as: I

  alias Exa.Color.Col1b

  # red green / blue peru
  @ramp new(
          5,
          5,
          :gray,
          Enum.reduce(0..4, <<>>, fn j, buf ->
            Enum.reduce(0..4, buf, fn i, buf ->
              Col1b.append_bin(buf, Col1b.new(i + 10 * j))
            end)
          end)
        )

  test "simple" do
    %I.Image{width: 5, height: 5, pixel: :gray, ncomp: 1, row: 5, buffer: buf} = @ramp

    assert <<0, 1, 2, 3, 4, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24, 30, 31, 32, 33, 34, 40, 41,
             42, 43, 44>> = buf
  end

  test "get set pixel" do
    img = @ramp
    assert 0 == get_pixel(img, {0, 0})
    assert 1 == get_pixel(img, {1, 0})
    assert 10 == get_pixel(img, {0, 1})
    assert 11 == get_pixel(img, {1, 1})
    assert 44 == get_pixel(img, {4, 4})

    assert_raise ArgumentError, fn -> get_pixel(img, {0, 10}) end

    new_img = set_pixel(img, {1, 2}, 99)
    assert 99 == get_pixel(new_img, {1, 2})

    new_img = set_pixel(img, {3, 2}, 47)
    assert 47 == get_pixel(new_img, {3, 2})
  end

  test "get set subimage" do
    img = @ramp
    {:ok, sub} = get_subimage!(img, {1, 2}, {2, 2})

    assert %I.Image{
             width: 2,
             height: 2,
             pixel: :gray,
             ncomp: 1,
             row: 2,
             buffer: <<21, 22, 31, 32>>
           } == sub

    assert :error == get_subimage!(img, {2, 1}, {7, 3})

    black = new(2, 3, :gray, <<0, 0, 0, 0, 0, 0>>)
    {:ok, new_img} = set_subimage!(img, {2, 1}, black)

    assert %I.Image{
             width: 5,
             height: 5,
             pixel: :gray,
             ncomp: 1,
             row: 5,
             buffer:
               <<0, 1, 2, 3, 4, 10, 11, 0, 0, 14, 20, 21, 0, 0, 24, 30, 31, 0, 0, 34, 40, 41, 42,
                 43, 44>>
           } = new_img
  end

  test "rotate reflect" do
    graze = new(2, 2, :gray, <<1, 2, 3, 4>>)

    reflect_x = %I.Image{graze | :buffer => <<2, 1, 4, 3>>}
    assert reflect_x == reflect_x(graze)

    reflect_y = %I.Image{graze | :buffer => <<3, 4, 1, 2>>}
    assert reflect_y == reflect_y(graze)

    rotate_180 = %I.Image{graze | :buffer => <<4, 3, 2, 1>>}
    assert rotate_180 == rotate_180(graze)

    rotate_90 = %I.Image{graze | :buffer => <<3, 1, 4, 2>>}
    assert rotate_90 == rotate_90(graze)

    rotate_270 = %I.Image{graze | :buffer => <<2, 4, 1, 3>>}
    assert rotate_270 == rotate_270(graze)
  end

  test "rows and pixels" do
    img = @ramp

    assert List.flatten([
             [0, 1, 2, 3, 4],
             [10, 11, 12, 13, 14],
             [20, 21, 22, 23, 24],
             [30, 31, 32, 33, 34],
             [40, 41, 42, 43, 44]
           ]) == get_pixels(img)
  end

  test "map pixels" do
    img = @ramp

    # darken, lighten
    dark = map_pixels(img, &Col1b.dark/1)

    assert %I.Image{
             width: 5,
             height: 5,
             pixel: :gray,
             ncomp: 1,
             row: 5,
             buffer:
               <<0, 0, 1, 1, 2, 5, 5, 6, 6, 7, 10, 10, 11, 11, 12, 15, 15, 16, 16, 17, 20, 20, 21,
                 21, 22>>
           } = dark

    pale = map_pixels(img, &Col1b.pale/1)

    assert %I.Image{
             width: 5,
             height: 5,
             pixel: :gray,
             ncomp: 1,
             row: 5,
             buffer:
               <<127, 128, 128, 129, 129, 132, 133, 133, 134, 134, 137, 138, 138, 139, 139, 142,
                 143, 143, 144, 144, 147, 148, 148, 149, 149>>
           } = pale
  end

  # test "map kernel" do
  #   # resize(@rgbp, 2)
  #   rgbp = @rgbp
  #   blur = map_kernel(rgbp, @blur_kernel3)

  #   assert %I.Image{
  #            width: 2,
  #            height: 2,
  #            pixel: :rgb,
  #            ncomp: 3,
  #            row: 6,
  #            buffer: <<202, 32, 29, 46, 205, 19, 213, 26, 32, 180, 126, 60>>
  #          } = blur
  # end

  test "sample" do
    img = @ramp

    # normalized and in first pixel
    assert 0 = sample(img, {0.1, 0.08}, true, :wrap_repeat, :interp_nearest)

    # not normalized but still nearest to first pixel
    assert 0 = sample(img, {0.7, 0.9}, false, :wrap_repeat, :interp_nearest)

    # normalized and in first pixel, bilinear but within 0.5 of origin
    assert 0 = sample(img, {0.1, 0.2}, true, :wrap_repeat, :interp_linear)

    # not mormalized but nearest to first pixel, 
    # but away from the corner bilinear and ~equidistant to all four pixels
    # 0, 1 .. 10, 11   average   23/4 = 5.75  trunc   5
    assert 5 = sample(img, {0.9999, 1.0001}, false, :wrap_repeat, :interp_linear)
  end

  test "upsize downsize resize" do
    img = resize(@ramp, 2)

    assert %I.Image{
             width: 10,
             height: 10,
             pixel: :gray,
             ncomp: 1,
             row: 10,
             buffer:
               <<0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 10, 10, 11, 11, 12,
                 12, 13, 13, 14, 14, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 20, 20, 21, 21, 22,
                 22, 23, 23, 24, 24, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 30, 30, 31, 31, 32,
                 32, 33, 33, 34, 34, 30, 30, 31, 31, 32, 32, 33, 33, 34, 34, 40, 40, 41, 41, 42,
                 42, 43, 43, 44, 44, 40, 40, 41, 41, 42, 42, 43, 43, 44, 44>>
           } == img

    res = resize(img, -2)
    assert @ramp == res
  end

  # TODO - other colormap formats ...
  # test "colormap to grayscale image" do
  #   Colormap3b.dark_red() |> from_cmap(2, 100) |> ImageWriter.to_file(png("dred_cmap"))
  #   Colormap3b.sat_magenta() |> from_cmap(2, 100) |> ImageWriter.to_file(png("smag_cmap"))
  #   Colormap3b.blue_white_red() |> from_cmap(2, 100) |> ImageWriter.to_file(png("bwr_cmap"))
  # end

  # # benchmark image access and processing ----------

  # # IO.inspect(sub, binaries: :as_binaries, limit: :infinity)

  # @tag benchmark: true
  # @tag timeout: 300_000
  # test "access benchmarks" do
  #   Benchee.run(
  #     benchmarks(),
  #     time: 20,
  #     save: [path: Path.join(@bench_dir, "image.benchee")],
  #     load: Path.join(@bench_dir, "image.latest.benchee")
  #   )
  # end

  # @n 128

  # defp benchmarks() do
  #   img = new(@n, @n, :rgb, @peru)
  #   red33 = new(3, 3, :rgb, @red)

  #   %{
  #     # access
  #     "get_pixel" => fn ->
  #       for i <- 0..(@n - 1) do
  #         for j <- 0..(@n - 1) do
  #           get_pixel(img, {i, j})
  #         end
  #       end
  #     end,
  #     "set_pixel" => fn ->
  #       for i <- 0..(@n - 1) do
  #         for j <- 0..(@n - 1) do
  #           set_pixel(img, {i, j}, @red)
  #         end
  #       end
  #     end,
  #     "get_subimage" => fn ->
  #       for i <- 0..(@n - 3) do
  #         for j <- 0..(@n - 3) do
  #           get_subimage!(img, {i, j}, 3, 3)
  #         end
  #       end
  #     end,
  #     "set_subimage" => fn ->
  #       for i <- 0..(@n - 3) do
  #         for j <- 0..(@n - 3) do
  #           set_subimage!(img, {i, j}, red33)
  #         end
  #       end
  #     end,

  #     # process
  #     "upsize" => fn -> resize(img, 2) end,
  #     "downsize" => fn -> resize(img, -2) end,
  #     "sample nearest" => fn ->
  #       for i <- 0..(@n - 1) do
  #         for j <- 0..(@n - 1) do
  #           sample(img, {i + 0.1, j + 0.7}, false, :wrap_repeat, :interp_nearest)
  #         end
  #       end
  #     end,
  #     "sample bilinear" => fn ->
  #       for i <- 0..(@n - 1) do
  #         for j <- 0..(@n - 1) do
  #           sample(img, {i + 0.1, j + 0.7}, false, :wrap_repeat, :interp_linear)
  #         end
  #       end
  #     end,
  #     "map_pixels" => fn ->
  #       map_pixels(img, &Col3b.to_gray(&1))
  #     end,
  #     "map_kernel3" => fn ->
  #       map_kernel(img, @blur_kernel3)
  #     end,
  #     "map_kernel5" => fn ->
  #       map_kernel(img, @blur_kernel5)
  #     end
  #   }
  # end
end

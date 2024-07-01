defmodule Exa.Image.BitmapTest do
  use ExUnit.Case

  import Exa.Types
  import Exa.Image.Bitmap

  alias Exa.Image.Types, as: I

  alias Exa.Color.Col1b
  alias Exa.Color.Col3b

  # {0}  01010000  0x50  80
  # {1}  10100000  0xA0 160
  # {2}  01010000  0x50  80
  # {3}  10100000  0xA0 160
  @chess_buf44 <<0::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1, 0::1, 0::1,
                 0::1, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1, 0::1,
                 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>

  @chess_bytes <<0x50, 0xA0, 0x50, 0xA0>>

  # {0}  00000000  0x00   0
  # {1}  00010000  0x10  16
  # {2}  00110000  0x30  48
  # {3}  01110000  0x70 112
  @count_buf44 <<0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1, 0::1,
                 0::1, 0::1, 0::1, 0::1, 0::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1,
                 1::1, 1::1, 0::1, 0::1, 0::1, 0::1>>

  test "simple" do
    count = new(4, 4, @count_buf44)
    assert %I.Bitmap{width: 4, height: 4, row: 1, buffer: <<0, 0x10, 0x30, 0x70>>} = count

    count_bits = get_bits(count)

    assert [
             [0, 0, 0, 0],
             [0, 0, 0, 1],
             [0, 0, 1, 1],
             [0, 1, 1, 1]
           ] = count_bits

    chess = new(4, 4, @chess_buf44)
    assert %I.Bitmap{width: 4, height: 4, row: 1, buffer: @chess_bytes} = chess

    chess_bits = get_bits(chess)

    assert [
             [0, 1, 0, 1],
             [1, 0, 1, 0],
             [0, 1, 0, 1],
             [1, 0, 1, 0]
           ] = chess_bits

    black = new(5, 5, 0)
    assert %I.Bitmap{width: 5, height: 5, row: 1, buffer: <<0, 0, 0, 0, 0>>} = black

    white = new(9, 9, 1)

    assert %I.Bitmap{
             width: 9,
             height: 9,
             row: 2,
             buffer:
               <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                 255, 255>>
           } = white

    # use a predicate to recreate the chessboard: is sum odd
    chess = new(4, 4, fn {i, j} -> is_odd(i + j) end)
    assert %I.Bitmap{width: 4, height: 4, row: 1, buffer: @chess_bytes} = chess
  end

  test "image" do
    chess = new(4, 4, @chess_buf44)
    chess_g = to_image(chess, :gray, Col1b.white(), Col1b.black())

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :gray,
             ncomp: 1,
             row: 4,
             buffer: <<0, 255, 0, 255, 255, 0, 255, 0, 0, 255, 0, 255, 255, 0, 255, 0>>
           } = chess_g

    chess_rgb = to_image(chess, :rgb, Col3b.white(), Col3b.black())

    assert %I.Image{
             width: 4,
             height: 4,
             pixel: :rgb,
             ncomp: 3,
             row: 12,
             buffer:
               <<0, 0, 0, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255,
                 255, 0, 0, 0, 0, 0, 0, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 255, 0,
                 0, 0, 255, 255, 255, 0, 0, 0>>
           } = chess_rgb
  end

  test "get set bit" do
    # {0}  01010000  0x50  60
    # {1}  10100000  0xA0 160
    # {2}  01010000  0x50  60
    # {3}  10100000  0xA0 160
    chess = new(4, 4, @chess_buf44)
    assert 0 == get_bit(chess, {0, 0})
    assert 1 == get_bit(chess, {0, 1})
    assert 0 == get_bit(chess, {0, 2})
    assert 1 == get_bit(chess, {0, 3})

    assert 1 == get_bit(chess, {3, 0})
    assert 0 == get_bit(chess, {3, 1})
    assert 1 == get_bit(chess, {3, 2})
    assert 0 == get_bit(chess, {3, 3})

    assert_raise ArgumentError, fn -> get_bit(chess, {0, -1}) end
    assert_raise ArgumentError, fn -> get_bit(chess, {4, 0}) end

    assert_set(chess, {0, 0}, 1)
    assert_set(chess, {1, 0}, 0)
    assert_set(chess, {2, 0}, 1)
    assert_set(chess, {3, 0}, 0)

    assert_set(chess, {0, 3}, 0)
    assert_set(chess, {1, 3}, 1)
    assert_set(chess, {2, 3}, 0)
    assert_set(chess, {3, 3}, 1)

    assert_raise ArgumentError, fn -> set_bit(chess, {0, -1}, 1) end
    assert_raise ArgumentError, fn -> set_bit(chess, {4, 0}, 1) end
  end

  defp assert_set(bmp, pos, b) do
    assert b == bmp |> set_bit(pos, b) |> get_bit(pos)
  end
end

defmodule Exa.Image.ConvolveTest do
  use ExUnit.Case

  import Exa.Image.Filter

  alias Exa.Math

  @int_kernel3 {
    {1, 2, 1},
    {2, 8, 2},
    {1, 2, 1}
  }

  @bad_kernel3 {
    {3.0, 0.0, 3.0},
    {0.5, 1.5, 0.5},
    {0.5, 0.5, 0.5}
  }

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

  test "min" do
    assert 0.05 = minimum(@blur_kernel3)
    assert 0.01 = minimum(@blur_kernel5)

    assert 1.0 == minimum(@int_kernel3)
    assert 0.0 = minimum(@bad_kernel3)
  end

  test "max" do
    assert 0.60 = maximum(@blur_kernel3)
    assert 0.16 = maximum(@blur_kernel5)

    assert 8.0 == maximum(@int_kernel3)
    assert 3.0 == maximum(@bad_kernel3)
  end

  test "sum normalize" do
    assert 1.0 == Math.fp_round(sum(@blur_kernel3))
    assert 1.0 == Math.fp_round(sum(@blur_kernel5))

    assert 20 == sum(@int_kernel3)
    assert 10.0 == sum(@bad_kernel3)

    assert_raise ArgumentError, fn -> ensure_bounds!(@int_kernel3) end
    assert_raise ArgumentError, fn -> ensure_bounds!(@bad_kernel3) end

    assert @blur_kernel3 = kern_round(normalize(@blur_kernel3))
    assert @blur_kernel5 = kern_round(normalize(@blur_kernel5))

    norm_int = normalize(@int_kernel3)
    assert 1.0 == sum(norm_int)

    assert {
             {0.05, 0.1, 0.05},
             {0.1, 0.4, 0.1},
             {0.05, 0.1, 0.05}
           } = norm_int

    norm_bad = normalize(@bad_kernel3)
    assert 1.0 == Math.fp_round(sum(norm_bad))

    assert {
             {0.3, 0.0, 0.3},
             {0.05, 0.15, 0.05},
             {0.05, 0.05, 0.05}
           } = kern_round(norm_bad)
  end
end

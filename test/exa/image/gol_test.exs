defmodule Exa.Image.GolTest do
  use ExUnit.Case

  alias Exa.Image.Gol

  @out_dir Path.join(["test", "output", "image", "gol"])

  @tag timeout: 30_000
  test "simple" do
    gol = Gol.random(100, 100)
    assert :ok == Gol.animate(@out_dir, "rnd_clp", gol, 200, :clamp0)
    assert :ok == Gol.animate(@out_dir, "rnd_cyc", gol, 200, :cyclic)
  end
end

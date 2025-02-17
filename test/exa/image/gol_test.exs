defmodule Exa.Image.GolTest do
  use ExUnit.Case

  alias Exa.Image.Gol

  @out_dir Path.join(["test", "output", "image", "gol"])

  @tag timeout: 30_000
  test "simple" do
    clamp = Gol.random(100, 100, 0.4, :clamp0)
    assert :ok == Gol.animate(@out_dir, "rnd_clp", clamp, 200)

    cyclic = Gol.random(100, 100, 0.4, :cyclic)
    assert :ok == Gol.animate(@out_dir, "rnd_cyc", cyclic, 200, :cyclic)
  end
end

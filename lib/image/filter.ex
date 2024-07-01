defmodule Exa.Image.Filter do
  @moduledoc """
  Kernel filters for image convolution.

  A kernel is a NxN array of floating-point weights.
  N should be odd, with `N = 2k + 1`.

  The sum of weights should not exceed 1.0.

  Integer weights are allowed. 
  There are functions to convert integral
  and unnormalized arrays into a valid kernel filter. 

  A kernel has the same shape and format as a _matrix,_
  but it is just a 2D array of weights,
  NOT a matrix structure in a vector space.

  The base format of a kernel is row-major vectors (image sequence).
  Transposed column-major vector format is also available,
  but the physical formats are indistinguishable.
  The semantics must be maintained by the usage.

  Convolutions are implemented by sliding
  an image window across the rows of the image,
  then multiplying by the kernel array (scalar _dot product_ ).
  The subimage is translated by the `slide` function.
  """
  require Logger
  use Exa.Constants
  use Exa.Image.Constants

  alias Exa.Types, as: E

  import Exa.Color.Types
  alias Exa.Color.Types, as: C

  alias Exa.Math

  # -----
  # types
  # -----

  @typedoc "A 1D vector of weights."
  @type kern1d() :: tuple()

  # allow integers initially, but they will be converted to floats in constructor
  defguard is_kern1d(k, n)
           when tuple_size(k) == n and (is_integer(elem(k, 0)) or is_weight(elem(k, 0)))

  defguard is_kern1d(k) when is_tuple(k) and is_kern1d(k, tuple_size(k))

  @typedoc "A 2D array of weights as vector of vectors."
  @type kern2d() :: tuple()
  defguard is_kern2d(k, n) when tuple_size(k) == n and is_kern1d(elem(k, 0), n)
  defguard is_kern2d(k) when is_tuple(k) and is_kern2d(k, tuple_size(k))

  # ---------
  # constants
  # ---------

  @doc "Gaussian blurring kernel."
  def gaussian_33() do
    new({
      {1, 2, 1},
      {2, 4, 2},
      {1, 2, 1}
    })
  end

  @doc "Gaussian blurring kernel (sigma = 1.0)."
  def gaussian_sigma1_55() do
    new({
      {2, 4, 5, 4, 2},
      {4, 9, 12, 9, 4},
      {5, 12, 15, 12, 5},
      {4, 9, 12, 9, 4},
      {2, 4, 5, 4, 2}
    })
  end

  @doc "Gaussian blurring kernel."
  def gaussian_55() do
    new({
      {1, 4, 7, 4, 1},
      {4, 16, 26, 16, 4},
      {7, 26, 41, 26, 7},
      {4, 16, 26, 16, 4},
      {1, 4, 7, 4, 1}
    })
  end

  @doc "Gaussian blurring kernel."
  def gaussian_77() do
    new({
      {0, 0, 1, 2, 1, 0, 0},
      {0, 3, 13, 22, 13, 3, 0},
      {1, 13, 59, 97, 59, 13, 1},
      {2, 22, 97, 159, 97, 22, 2},
      {1, 13, 59, 97, 59, 13, 1},
      {0, 3, 13, 22, 13, 3, 0},
      {0, 0, 1, 2, 1, 0, 0}
    })
  end

  @doc "Sobel X-edge detection kernel."
  def sobel_x_33() do
    new({
      {1, 2, 1},
      {0, 0, 0},
      {-1, -2, -1}
    })
  end

  @doc "Sobel Y-edge detection kernel."
  def sobel_y_33() do
    transpose(sobel_x_33())
  end

  @doc "Laplacian with negative central value."
  def neg_laplacian_33() do
    new({
      {0, 1, 0},
      {1, -4, 1},
      {0, 1, 0}
    })
  end

  @doc "Laplacian of Gaussian with negative central value (sigma = 1.4)."
  def neg_log_99() do
    new({
      {0, 0, 3, 2, 2, 2, 3, 0, 0},
      {0, 2, 3, 5, 5, 5, 3, 2, 0},
      {3, 3, 5, 3, 0, 3, 5, 3, 3},
      {2, 5, 3, -12, -23, -12, 3, 5, 2},
      {2, 5, 0, -23, -40, -23, 0, 5, 2},
      {2, 5, 3, -12, -23, -12, 3, 5, 2},
      {3, 3, 5, 3, 0, 3, 5, 3, 3},
      {0, 2, 3, 5, 5, 5, 3, 2, 0},
      {0, 0, 3, 2, 2, 2, 3, 0, 0}
    })
  end

  # ------------
  # constructors
  # ------------

  @doc "Create a new kernel and normalize weights."
  @spec new(kern2d()) :: kern2d()
  def new(k2) when is_kern2d(k2), do: normalize(k2)

  # TODO - combine separable filters?
  # def new(xk1, yk1) when is_kern1d(xk1) and is_kern1d(yk1) do
  #   { 
  #     }
  # end

  # ----------------
  # public functions
  # ----------------

  @doc "Raise error if sum of weights is outside bounds (-1.0, 1.0)."
  @spec ensure_bounds!(kern2d(), E.epsilon()) :: nil
  def ensure_bounds!(k2, eps \\ @epsilon) do
    sow = sum(k2)
    bet = Math.between(-1.0, sow, 1.0, eps)

    if bet in [:below_min, :above_max] do
      msg = "Kernel sum of weights out-of-bounds: #{sow}"
      Logger.error(msg)
      raise ArgumentError, message: msg
    end
  end

  @doc """
  Normalize if there is any integer weight or the
  sum of absolute weights is outside bounds [0.0, 1.0).
  Raises error if weights are all approximately zero.
  """
  @spec normalize(kern2d(), E.epsilon()) :: kern2d()
  def normalize(k2, eps \\ @epsilon) do
    sow = sum_abs(k2)

    if sow < eps do
      msg = "Kernel has zero weights #{inspect(k2)}"
      Logger.error(msg)
      raise ArgumentError, message: msg
    end

    bet = Math.between(-1.0, sow, 1.0, eps)

    if integer?(k2) or bet in [:below_min, :above_max] do
      mul(1.0 / sow, k2)
    else
      k2
    end
  end

  # --------
  # reducers
  # --------

  @doc "Reduce over a kernel."
  @spec reduce(kern2d(), any(), (C.weight(), any() -> any())) :: any()
  def reduce(k2, init, kfun) do
    Exa.Tuple.reduce(k2, init, fn k1, acc ->
      Exa.Tuple.reduce(k1, acc, kfun)
    end)
  end

  # test if any weight is an integer."
  @spec integer?(kern2d()) :: bool()
  defp integer?(k2), do: reduce(k2, true, &(&2 or is_integer(&1)))

  @doc "Get the signed sum of weights. Result may be zero for valid kernel."
  @spec sum(kern2d()) :: C.weight()
  def sum(k2), do: reduce(k2, 0.0, &Kernel.+/2)

  @doc "Get the sum of absolute weights. Never zero for valid kernel."
  @spec sum_abs(kern2d()) :: C.weight()
  def sum_abs(k2), do: reduce(k2, 0.0, &(&2 + abs(&1)))

  @doc "Get the minimum of weights."
  @spec minimum(kern2d()) :: C.weight()
  def minimum(k2), do: reduce(k2, 1.0e10, &Kernel.min/2)

  @doc "Get the maximum of weights."
  @spec maximum(kern2d()) :: C.weight()
  def maximum(k2), do: reduce(k2, -1.0e10, &Kernel.max/2)

  # -------
  # mappers
  # -------

  @doc "Map a scalar function across the kernel."
  @spec map(kern2d(), (C.weight() -> C.weight())) :: kern2d()
  def map(arr, w_fun) do
    Exa.Tuple.map(arr, fn wvec ->
      Exa.Tuple.map(wvec, w_fun)
    end)
  end

  @doc "Multiply by a scalar."
  @spec mul(C.weight(), kern2d()) :: kern2d()
  def mul(x, arr), do: map(arr, &(x * &1))

  @doc "Round to an epsilon value."
  @spec kern_round(kern2d(), E.epsilon()) :: kern2d()
  def kern_round(arr, eps \\ @epsilon), do: map(arr, &Math.fp_round(&1, eps))

  # ---------
  # transpose
  # ---------

  @doc "Transpose an array from column-vector to row-column format, or vice-versa."
  @spec transpose(kern2d()) :: kern2d()

  def transpose({
        {w1_1, w1_2, w1_3},
        {w2_1, w2_2, w2_3},
        {w3_1, w3_2, w3_3}
      }) do
    {
      {w1_1, w2_1, w3_1},
      {w1_2, w2_2, w3_2},
      {w1_3, w2_3, w3_3}
    }
  end

  def transpose(wvecs) do
    0..tuple_size(wvecs)
    |> Enum.reduce([], fn e, tvecs ->
      [
        wvecs
        |> Enum.reduce([], fn wvec, ws -> [elem(wvec, e) | ws] end)
        |> Enum.reverse()
        |> List.to_tuple()
        | tvecs
      ]
    end)
    |> Enum.reverse()
    |> List.to_tuple()
  end
end

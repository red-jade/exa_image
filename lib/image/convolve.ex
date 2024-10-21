defmodule Exa.Image.Convolve do
  @moduledoc """
  A convolution function to combine a filter kernel with a sub-image array.

  The base format of a kernel is row-major vectors (image sequence).
  Transposed column-major vector format is also available,
  but the physical formats are indistinguishable.
  The semantics must be maintained by the usage.

  Sub-image base format is column-major format.
  Column-major format is important because it supports
  sliding the image window by deleting & appending a column vector
  in natural image order.

  Convolutions are implemented by sliding
  an image window across the rows of the image,
  then multiplying by the kernel array (scalar _dot_ product).

  The subimage is translated by the `slide` function
  to move to the next pixel.
  """
  require Logger
  use Exa.Constants
  use Exa.Image.Constants

  import Exa.Types

  import Exa.Color.Types
  alias Exa.Color.Types, as: C
  alias Exa.Space.Types, as: S

  alias Exa.Image.Filter, as: K
  alias Exa.Image.Types, as: I

  alias Exa.Math
  alias Exa.Binary

  alias Exa.Color.Pixel
  alias Exa.Color.Colorb
  alias Exa.Color.Colorf
  # alias Exa.Color.Col3b

  alias Exa.Image.Image
  alias Exa.Image.Filter

  # -----
  # types
  # -----

  # 1D vector of float colors."
  @typep col1d() :: tuple()
  defguard is_col1d(c, n) when is_tuple(c) and tuple_size(c) == n and is_colorf(elem(c, 0))

  # 2D array of float colors (image) as a vector of vectors."
  @typep col2d() :: tuple()
  defguard is_col2d(s, n) when is_tuple(s) and tuple_size(s) == n and is_col1d(elem(s, 0), n)

  # pixel cache for memoized access
  @typep pix_cache() :: %{S.pos2i() => C.colorb()}

  # tile function for convolving a sub-image to a pixel value
  @typep tile_fun() :: (%I.Image{} -> C.color())

  # ----------------
  # public functions
  # ----------------

  @doc """
  A subimage convolution.

  Each new pixel is the result of multiplying
  an NxN kernel array across the local neighborhood 
  of the source pixel. 

  The multiplication is scalar dot product.

  The kernel is `n x n`, where _n_ is odd, so `n = 2k + 1`.
  For n = 1, k = 0, the kernel degenerates into a scalar multiplication,
  and the convolution becomes a simple color function, 
  so the `map_pixels` function should be used instead.
  In general, for positive k=1,2,3.. the kernel is 3x3, 5x5, ..etc.
  """
  @spec map_kernel(%I.Image{}, K.kern2d()) :: %I.Image{}
  def map_kernel(%I.Image{} = img, kernel) when rem(tuple_size(kernel), 2) == 1 do
    Filter.ensure_bounds!(kernel)
    kern_fun = fn sub -> kernel |> convolve_NxN(sub) |> Colorf.blend() end
    map_convolve(img, tuple_size(kernel), kern_fun)
  end

  @doc """
  Image processing by a local operations.
  A local_op is a type of convolution
  with specific rules about how a pixel
  is changed in response to its local neighborhood.

  Each new pixel is the result of applying 3 steps:
  - apply an input function to each pixel 
    to create a linear measure (greyscale 1-byte sub-image)
  - threshold the values of the measure in the local neighborhood 
    to produce an image of signs (-1,0,+1)
  - make a decision based on the counts (and layout)
    for how to transform the pixel with an output function

  There are 4 concrete examples to provide useful templates,
  but the local_op is more general.

  (1) Conway's Game of Life (GoL) uses a specific
  decision condition on the neighborhood to update the image.

  (2,3) Erode-Dilate use a simple total count of neighbors
  below/equal/above a threshold value
  to decide the new value.

  (4) Contouring keeps pixels 'on' a countour value.
  There are a few different ways to choose contour pixels, for example:
  - Pixel equal to the contour value, 
    with at least one +ve (above) and at least one -ve (below) neighbour. 
  - Just use the net total of +- levels with respect to the contour
    and keep pixels with value 0, or perhaps [-1,0,+1]
    (compared to extreme values -9..+9 for N=3, k=1).

  For example, for a 3x3 neighborhood [k=1, N=2k+1], 
  there are 8 neighbors [N^2-1 = 4k^2 + 4k + 1], 
  and the count is the relative to the threshold 4 
  [(N^2-1)/2 = 2k(k+1)].
  Then the test becomes:
  - below < 4   Erode  (switch to -)
  - equal = 4      
  - above > 4   Dilate (switch to +)      

  Erode is reducing (removing, switching off) a pixel
  if it is below the critical count, 
  but leaving others the same.

  Dilate is increasing (adding, switching on) a pixel
  if it is above the critical count, 
  but leaving others the same.

  Successive cycles of erode-dilate
  have the effect of smoothing boundaries in the image.
  Smoothing means removing wrinkles
  to make a smooth contour of the scalar measure.
  """
  @spec local_op(%I.Image{}, I.size(), fun(), fun(), fun(), fun()) ::
          %I.Image{}
  def local_op(%I.Image{} = img, n, measure, threshold, decision, expand)
      when div(n, 2) == 1 and
             is_function(measure, 1) and is_function(threshold, 1) and
             is_function(decision, 1) and is_function(expand, 1) do
    local_fun = local_fun(measure, threshold, decision, expand)
    map_convolve(img, n, local_fun)
  end

  # def erode(%I.Image{pixel: pix} = img, n \\ 3) do
  #   local_op(img, n, luma_fun(pix), thresh2_fun(), erode_fun(), expand2_fun())
  # end

  # local_fun generates a function that is used in a local_op
  #
  # the sub-image is NxN, where N=2k+1
  #
  # the local_op function takes a general sub-image then applies four functions:
  # - scalar projection that transforms the pixel to a byte value at each cell
  # - thresholding function that takes a byte sub-image and 
  #   typically creates a binary (0,1) or ternary (-1,0,+1) value at each cell
  # - decision function that takes a threshold sub-image and produces a change result
  #   typically a binary (live/die), ternary (decrement,same,increment) outcome
  # - expand function that applies a decision result to change the original pixel
  #   into an output pixel for the new image

  @spec local_fun(fun(), fun(), fun(), fun()) :: tile_fun()
  defp local_fun(fmeasure, fthreshold, fdecision, fexpand) do
    fn %I.Image{width: n, height: n} = sub when is_int_odd(n) ->
      sub
      |> Image.map_pixels(fmeasure)
      |> Map.fetch!(:buffer)
      |> Binary.to_bytes()
      |> fthreshold.()
      |> fdecision.()
      |> fexpand.()
    end
  end

  # pixel fun that converts to a greyscale

  # defp luma_fun(:grey) do
  #   fn grey when is_byte(grey) -> grey end
  # end

  # defp luma_fun(pix) do
  #   3 = Pixel.ncomp(pix)
  #   fn col when is_tuple(col) and tuple_size(col) == 3 -> Col3b.luma(col, pix) end
  # end

  # byte function that classifies into 0 or 1
  # based on < level, or >= level (default 128)
  # output is a list of integer bits 0 or 1
  # defp thresh2_fun(level \\ 128) do
  #   fn sub_bytes when is_list(sub_bytes) ->
  #     Enum.map(sub_bytes, fn
  #       b when b < level -> 0
  #       _ -> 1
  #     end)
  #   end
  # end

  # byte function that classifies into -1, 0, +1
  # based on: b < low, low <= b <= hi, b > hi
  # output is a list of integers -1, 0, 1
  # defp thresh3_fun(lo \\ 127, hi \\ 128) when hi >= lo do
  #   fn sub_bytes when is_list(sub_bytes) ->
  #     Enum.map(sub_bytes, fn
  #       b when b < lo -> -1
  #       b when b > hi -> 1
  #       _ -> 0
  #     end)
  #   end
  # end

  # defp expand2_fun(fgcol \\ 255, bgcol \\ 255),
  #   do: fn
  #     0 -> bgcol
  #     1 -> fgcol
  #   end

  # defp expand3_fun(locol \\ 0, oncol \\ 255, hicol \\ 0),
  #   do: fn
  #     -1 -> locol
  #     0 -> oncol
  #     1 -> hicol
  #   end

  # evaluates sign3 list to give live (true) / die (false) outcome ...

  # erode will kill cells (switch 1 to 0) 
  # if they have fewer than half neighbors alive
  # defp erode_fun() do
  #   fn signs2 when is_list(signs2) ->
  #     # mid is the index of the center cell 
  #     # and the cut for the size of neighborhood
  #     mid = signs2 |> length() |> div(2)
  #     if Enum.sum(signs2) < mid, do: 0, else: Enum.at(signs2, mid)
  #   end
  # end

  # dilate will grow cells (switch from 0 to 1)
  # if they have more than half neighbors alive
  # defp dilate_fun() do
  #   fn signs2 when is_list(signs2) ->
  #     # mid is the index of the center cell 
  #     # and the cut for the size of neighborhood
  #     mid = signs2 |> length() |> div(2)
  #     if Enum.sum(signs2) > mid, do: 1, else: Enum.at(signs2, mid)
  #   end
  # end

  # game of life will:
  # - kill living cells that do not have 2 or 3 neighbors
  # - grow dead cells that have exactly 3 neighbors
  # use the whole sum, including the central cell
  # - 3 will result in live cell 1
  # - 4 will stay the same 0,1
  # - all other values die 0
  # the central existing value is at position sub-image length % 2
  # defp gol(signs2) when is_list(signs2) do
  #   case Enum.sum(signs2) do
  #     3 -> 1
  #     4 -> Enum.at(signs2, signs2 |> length() |> div(2))
  #     _ -> 0
  #   end
  # end

  @doc """
  A generalized subimage convolution.

  Each new pixel is the result of applying a general function
  across the local `n x n` neighborhood of the source pixel,
  where _n_ is odd, so `n = 2k + 1`.

  The convolution function may be a kernel filter,
  like blur and edge detection,
  or it can be a general mapping.
  For example, implementing cellular automata
  or thresholding and branching, like erode-dilate.
  """
  @spec map_convolve(%I.Image{}, I.size(), tile_fun()) :: %I.Image{}
  def map_convolve(%I.Image{width: w, height: h, pixel: pix} = img, n, tile_fun)
      when is_int_odd(n) and is_function(tile_fun, 1) do
    k = div(n, 2)

    buf =
      Enum.reduce(0..(h - 1), <<>>, fn j, out ->
        # build initial subimage centered on {0,0}
        # first y column vec will get replaced at beginning of row
        # but at least it warms up the cache :)
        {cvecs, cache} =
          Enum.reduce((-k - 1)..(k - 1), {[], %{}}, fn i, {cvecs, cache} ->
            {cvec, cache} = subimage_1xN(img, i, 0, w, h, k, cache)
            {[cvec | cvecs], cache}
          end)

        sub = cvecs |> Enum.reverse() |> List.to_tuple()

        {_, _, out} =
          Enum.reduce(0..(w - 1), {sub, cache, out}, fn i, {sub, cache, out} ->
            {cvec, cache} = subimage_1xN(img, i + 1, j, w, h, k, cache)
            sub = slide(sub, cvec)
            col = tile_fun.(sub)
            out = Colorb.append_bin(pix, out, col)
            {sub, cache, out}
          end)

        out
      end)

    %I.Image{img | :buffer => buf}
  end

  # ----------------
  # public functions
  # ----------------

  # Slide a subimage in column-major vector format.
  # Remove the first (low i) vector 
  # and append a new vector as the last element (high i).
  @spec slide(col2d(), col1d()) :: col2d()

  defp slide({_cvec0, cvec1, cvec2}, cnew), do: {cvec1, cvec2, cnew}

  defp slide(cvecs, cnew) do
    1..(tuple_size(cvecs) - 1)
    |> Enum.reduce([cnew], fn e, vs -> [elem(cvecs, e) | vs] end)
    |> Enum.reverse()
    |> List.to_tuple()
  end

  # Convolve (pointwise dot-product) 
  # for an NxN kernel of weights with an NxN subimage.
  # The matrix and the subimage are in the same format 
  # (i.e. column-vector).

  # The result is a weighted-color list, 
  # which must be blended to get a final pixel value.
  @spec convolve_NxN(K.kern2d(), col2d()) :: C.color_weights()

  defp convolve_NxN({wvec1, wvec2, wvec3}, {cvec1, cvec2, cvec3}) do
    [] |> wcol_zip(wvec1, cvec1) |> wcol_zip(wvec2, cvec2) |> wcol_zip(wvec3, cvec3)
  end

  defp convolve_NxN(wvecs, cvecs) when tuple_size(wvecs) == tuple_size(cvecs) do
    Enum.reduce(0..(tuple_size(wvecs) - 1), [], fn e, wcols ->
      wcol_zip(wcols, elem(wvecs, e), elem(cvecs, e))
    end)
  end

  # merge weights and colors 
  # prepend to a weighted-color list
  defp wcol_zip(wcols, ws, cs) when tuple_size(ws) == tuple_size(cs) do
    Enum.reduce(0..(tuple_size(ws) - 1), wcols, fn e, wcols ->
      [{elem(ws, e), elem(cs, e)} | wcols]
    end)
  end

  # Get 1xN subimage column-vector (i-constant, j-varying) 
  # centered on an image positon.

  # N such vectors can be assembled into an NxN subimage.
  # Out-of-bounds input values are allowed for i, but not j.
  # All out-of-bounds values get clamped to the border.

  # Thread a cache through the construction to optimize border pixels

  @spec subimage_1xN(%I.Image{}, integer(), integer(), I.size(), I.size(), I.size(), pix_cache()) ::
          {col1d(), pix_cache()}
  defp subimage_1xN(img, i, j, w, h, k, cache) when w > 1 and h > 1 do
    # y-dimension is n, where n=2k+1
    # i out of range by +-k, but j must be within image
    if i < -k - 1 or i > w - 1 + k or j < 0 or j >= h do
      msg =
        "Image coordinates out of bounds, " <>
          "dimensions (0..#{img.width - 1}, 0..#{img.height - 1}), position {#{i},#{j}}."

      Logger.error(msg)
      raise ArgumentError, message: msg
    end

    ii = Math.clamp_(0, i, w - 1)
    js = Enum.map(-k..+k, &Math.clamp_(0, j + &1, h - 1))

    # fetch the pixels individually, probably fast enough
    # but cache the border, which is accessed multiple times
    {pixels, cache} =
      Enum.reduce(js, {[], cache}, fn jj, {pixels, cache} ->
        {p, cache} = get_pixel(img, {ii, jj}, cache)
        {[Pixel.to_colorf(p) | pixels], cache}
      end)

    {pixels |> Enum.reverse() |> List.to_tuple(), cache}
  end

  # memoized wrapper to get_pixel
  # the border pixels are accessed many times: edges O(N^2), corners O(N^3)
  # central pixels accessed O(N) times for a sliding NxN subimage convolution
  # just cache borders for now, otherwise the cache expands to include all pixels
  @spec get_pixel(%I.Image{}, S.pos2i(), pix_cache()) :: {C.colorb(), pix_cache()}

  defp get_pixel(%I.Image{}, pos, cache) when is_map_key(cache, pos) do
    {Map.fetch!(cache, pos), cache}
  end

  defp get_pixel(%I.Image{width: w, height: h} = img, {i, j} = pos, cache)
       when i == 0 or i == w - 1 or j == 0 or j == h - 1 do
    pix = Image.get_pixel(img, pos)
    {pix, Map.put(cache, pos, pix)}
  end

  defp get_pixel(img, pos, cache) do
    {Image.get_pixel(img, pos), cache}
  end
end

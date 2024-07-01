defmodule Exa.Image.ImagePara do
  @moduledoc "Utilities for parallel operations on images."

  use Exa.Image.Constants

  alias Exa.Types, as: E
  alias Exa.Image.Types, as: I

  alias Exa.Color.Types, as: C

  alias Exa.Image.Image

  @para_timeout 5_000

  # ----------------
  # public functions
  # ----------------

  # TODO - map pixels with alpha blend function

  @doc """
  Parallel version of `map_pixels`.
  """
  @spec map_pixels(%I.Image{}, C.pixel_fun(), I.npara(), E.timeout1()) :: I.image_timeout()
  def map_pixels(%I.Image{} = img, pixfun, n \\ :nproc, timeout \\ @para_timeout) do
    img |> Image.split_n(n) |> map_para(&Image.map_pixels(&1, pixfun), timeout)
  end

  # -----------------
  # private functions
  # -----------------

  # generalized parallel map for images
  @spec map_para([%I.Image{}], I.image_fun(), E.timeout1()) :: I.image_timeout()
  defp map_para(args, fun, timeout) do
    self = self()
    narg = length(args)
    seqargs = Enum.zip(1..narg, args)
    # no real need to use the pid if everything works fine
    # but maybe there are multiple parallel processes
    # with timeouts and late messages
    # so use belt and braces with id and pid
    # another approach is to use a generated reference
    [pid1 | pids] =
      Enum.map(seqargs, fn {id, arg} ->
        spawn(fn -> send(self, {self(), id, fun.(arg)}) end)
      end)

    seqpids = Enum.zip(2..narg, pids)
    img1 = recv(1, pid1, timeout)

    # Note that the result is assembled incrementally:
    # wait for the next fragment to arrive, then append it to the image.
    # This means the final image is being reassembled in this self process
    # while later fragments are still being calculated in other processes.
    # Fragments that arrive early out-of-order wait in this process mailbox.
    # Contrast with the simpler implementation that waits for all fragments
    # then merges them at the end.

    Enum.reduce(seqpids, img1, fn {id, pid}, img ->
      next = recv(id, pid, timeout)
      append(img, next)
    end)
  end

  @spec recv(pos_integer(), pid(), E.timeout1()) :: I.image_timeout()
  defp recv(id, pid, timeout) do
    receive do
      {^pid, ^id, result} -> result
    after
      timeout -> :timeout
    end
  end

  @spec append(I.image_timeout(), I.image_timeout()) :: I.image_timeout()
  defp append(:timeout, _), do: :timeout
  defp append(_, :timeout), do: :timeout
  defp append(img1, img2), do: Image.merge([img1, img2])
end

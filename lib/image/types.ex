defmodule Exa.Image.Types do
  @moduledoc "Types for image formats."

  import Exa.Types
  alias Exa.Types, as: E

  # alias Exa.Color.Types, as: C

  @typedoc "A video format that determines the dimensions of an image frame."
  @type video_format() ::
          :video_sd
          | :video_480p
          | :video_hd
          | :video_720p
          | :video_fhd
          | :video_1080p
          | :video_qhd
          | :video_1440p
          | :video_2k
          | :video_4k
          | :video_uhd
          | :video_2160p
          | :video_8k
          | :video_fuhd
          | :video_4320p

  @typedoc """
  Width and height, in units of pixels.

  A pixel unit can be:
  - multibyte (color images) 
  - single byte (1-channel images) 
  - bit (for bitmaps)
  """
  @type size() :: E.count1()
  defguard is_size(d) when is_count1(d)

  @typedoc "Dimensions of an image or bitmap."
  @type dimensions() :: {width :: I.size(), height :: I.size()}

  defguard is_dims(w, h) when is_size(w) and is_size(h)

  @type wrap() ::
          :wrap_repeat
          | :wrap_repeat_mirror
          | :wrap_clamp_edge
  # TODO - {:wrap_clamp_border, C.col3b()}

  @type interp() :: :interp_nearest | :interp_linear

  @type orient() :: :vertical | :horizontal

  @typedoc """
  The nunmber of processes to use for parallel computation.

  If the number is given as `:nproc,` 
  then the number of logical processors on the cpu hardware is used.
  The value `:nproc2` means double the number of processors.

  A value of `:nproc` might be appropriate 
  when there are multiple top-level parallel processes running concurrently.
  A value of `:nproc2` might be better,
  if there is only one top-level parallel process running.
  """
  @type npara() :: :nproc | :nproc2 | E.count1()

  # -----
  # image
  # -----

  defmodule Image do
    @moduledoc """
    A simple image type.

    `ncomp` is the number of components (channels) per-pixel. 
    Images with 1, 2, 3 or 4 components are supported.

    All images are assumed to have 1-byte per-component.
    12/16-bit per-component are not supported at this time.
    Varying component sizes, like 5-6-5 RGB are not supported.

    For 1-bit per-pixel images, use the `Bitmap` module.

    There is no padding for alignment at larger boundaries (2/4/8 bytes, or word).

    `row` is the byte size of one row of the image.

    `image.row = image.width * image.ncomp`

    Total byte size:

    `byte_size(image.buffer)` = `image.height * image.row`
    """
    alias Exa.Types, as: E
    alias Exa.Color.Types, as: C
    alias Exa.Image.Types, as: I

    @enforce_keys [:width, :height, :pixel, :ncomp, :row, :buffer]
    defstruct [:width, :height, :pixel, :ncomp, :row, :buffer]

    @type t() :: %Image{
            width: I.size(),
            height: I.size(),
            pixel: C.pixel(),
            ncomp: C.ncomp(),
            row: E.bsize(),
            buffer: binary()
          }
  end

  defguard is_image(img) when is_struct(img, Image)

  @type image_fun() :: (%Image{} -> %Image{})

  @type image_timeout() :: :timeout | %Image{}

  # ------
  # bitmap
  # ------

  defmodule Bitmap do
    @moduledoc """
    A simple bitmap type.

    The bits are not interpreted - there is no semantic pixel type.
    The bits could be black/white or transparent/opaque.

    A bitmap can be interpreted by expanding to a full `Image`, 
    using foreground (1) and background (0) colors 
    to create the target pixel type.

    A bitmap can also be used as a tranparency (selection) mask 
    to combine two color images.

    Rows are padded to the nearest byte.
    `row` is the byte size of one row of the image.

    Total byte size = `byte_size(image.buffer)` = `image.height * image.row`
    """
    alias Exa.Types, as: E
    alias Exa.Image.Types, as: I

    @enforce_keys [:width, :height, :row, :buffer]
    defstruct [:width, :height, :row, :buffer]

    @type bitmap() :: %Bitmap{
            width: I.size(),
            height: I.size(),
            row: E.bsize(),
            buffer: binary()
          }
  end

  defguard is_bitmap(bmp) when is_struct(bmp, Bitmap)
end

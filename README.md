# EXA Image

𝔼𝕏tr𝔸 𝔼li𝕏ir 𝔸dditions (𝔼𝕏𝔸)

EXA project index: [exa](https://github.com/red-jade/exa)

Core utilities for 2D bitmaps, images and video.

Module path: `Exa.Image`

## Features

Bitmap:

- bitmap: create, access, output to ascii art and image
- bitmap/image: bitmap to alpha, bitmap matte composition

Image:

- all 1,3,4 byte pixel types
- image: create, access, sub-image
- basic ops: crop, reflect, rotate, histogram
- colormap to image
- map/reduce over pixels
- sample nearest/bilinear
- convolve kernels over subimages
- downsize, upsize and resize (integer multiple only)
- split and merge for chunked parallel processing

Image I/O:
- fork of E3D to read/write PNG/TIF/BMP formats
- read/write _portable_ PBM/PGM/PBM text/binary formats

Video (only if [ffmpeg](https://ffmpeg.org/download.html) is installed):
- create video from image files
- probe video for information

## Building

To bootstrap an `exa_xxx` library build, 
you must run `mix deps.get` twice.

## E3D License

The image subset of E3D was copied (forked) 
from the Wings3D repo on 23 November 2023 (v2.3):

https://github.com/dgud/wings

See the file `src/e3d/license.terms` for licensing.

See source file headers for author credit and copyright:

All files are:<br>
Copyright (c) Dan Gudmundsson

## EXA License

EXA source code is released under the MIT license.

EXA code and documentation are:<br>
Copyright (c) 2024 Mike French

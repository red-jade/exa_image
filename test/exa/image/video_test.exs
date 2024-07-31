defmodule Exa.Image.VideoTest do
  use ExUnit.Case

  use Exa.Image.Constants

  alias Exa.Image.Video

  @png_in_dir ["test", "input", "image", "png"]
  @mp4_in_dir ["test", "input", "image", "mp4"]

  @mp4_out_dir ["test", "output", "image", "mp4"]

  def file_glob(dir, name) do
    Exa.File.join(@png_in_dir ++ [dir], name <> "-*", @filetype_png)
  end

  def file_iseq(dir, name) do
    Exa.File.join(@png_in_dir ++ [dir], name <> "_%04d", @filetype_png)
  end

  def in_mp4(name) do
    Exa.File.join(@mp4_in_dir, name, @filetype_mp4)
  end

  def out_mp4(name) do
    Exa.File.join(@mp4_out_dir, name, @filetype_mp4)
  end

  test "installed" do
    cmd = Video.installed(:ffmpeg)

    if is_nil(cmd) do
      IO.puts("FFMPEG not installed")
    else
      IO.inspect(cmd, label: "FFMPEG")
    end
  end

  test "glider" do
    # globbing not available on Windows
    # glob = file_glob("glider", "glider")
    seq = file_iseq("glider", "glider")
    mp4 = out_mp4("glider")

    args = [
      loglevel: "error",
      overwrite: "y",
      framerate: 12,
      # pattern_type: "glob",
      pattern_type: "sequence",
      start_number: "0001",
      i: seq,
      "c:v": "libx264",
      r: 12,
      pix_fmt: "yuv420p"
    ]

    Video.from_files(mp4, args)
  end

  test "info" do
    info = Video.info(in_mp4("glider"), loglevel: "error")

    format = info.format
    stream = hd(info.streams)

    assert %{filename: "test/input/image/mp4/glider.mp4", size: "7505"} = format

    assert %{
             width: 200,
             height: 200,
             codec_name: "h264",
             pix_fmt: "yuv420p",
             duration: "12.500000"
           } = stream
  end

  @tag timeout: 15_000
  test "play" do
    glider = in_mp4("glider")

    info = Video.info(glider, loglevel: "error")
    {time, ""} = Float.parse(info.format.duration)
    wait = round(time * 1000.0)

    ret = Video.play(glider, loglevel: "error")
    IO.inspect(ret, label: "play")
    Process.sleep(wait)
  end
end

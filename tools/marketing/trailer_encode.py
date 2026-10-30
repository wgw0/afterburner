"""
Afterburner: encodes a folder of frame_NNNN.png into an H.264 MP4 with Blender's sequencer (so no separate
ffmpeg is needed). Called by trailer_compose.py.

  blender -b --factory-startup --python tools/marketing/trailer_encode.py -- <frames dir> <out.mp4> <fps>
"""

import glob
import os
import sys

import bpy

frames_dir, out, fps = sys.argv[sys.argv.index("--") + 1:][:3]
files = sorted(os.path.basename(f) for f in glob.glob(os.path.join(frames_dir, "frame_*.png")))
scene = bpy.context.scene
editor = scene.sequence_editor_create()
strips = editor.strips if hasattr(editor, "strips") else editor.sequences
strip = strips.new_image("Frames", os.path.join(frames_dir, files[0]), 1, 1)
for f in files[1:]:
    strip.elements.append(f)
scene.frame_start, scene.frame_end = 1, len(files)
scene.render.fps = int(fps)
first = bpy.data.images.load(os.path.join(frames_dir, files[0]))
scene.render.resolution_x, scene.render.resolution_y = first.size
scene.render.resolution_percentage = 100
settings = scene.render.image_settings
if hasattr(settings, "media_type"):
    settings.media_type = "VIDEO"
settings.file_format = "FFMPEG"
ff = scene.render.ffmpeg
ff.format = "MPEG4"
ff.codec = "H264"
ff.constant_rate_factor = "HIGH"
ff.ffmpeg_preset = "GOOD"
ff.audio_codec = "NONE"
scene.view_settings.view_transform = "Standard"  # the frames are already graded
scene.render.filepath = out
bpy.ops.render.render(animation=True)
print("encoded", out)

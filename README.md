# Flipbook

Tested on Godot 4.7.

Plays frame by frame animations on a loop, without keeping every frame in memory.

The idea is the one of a flip book: a sequence of images shown one after another. The problem is
that at high resolutions those images are far too heavy to all sit in memory.

This tool works around it in three ways:

- it **cuts** every frame into tiles and packs them into a few large images;
- it **drops the duplicates**: the parts that do not change from one frame to the next are stored
  only once;
- it **loads only what is needed right now**: a buffering window slides along with the animation
  and throws away the rest.

The result is a node you drop in the scene, lit by `Light2D` like any other sprite, playing
animations that would not otherwise fit.

---

## How to use it

The work is in three steps: **draw the images**, **prepare the atlas** once, and **put the node in
the scene**.

### Step 1 — the images

Two folders are needed, one for the frames and one for the normal maps:

```
diffuse/   frame_000.png, frame_001.png, ...
normal/    frame_000.png, frame_001.png, ...
```

Same names in both folders, one file per frame, in alphabetical order. The two folders can sit
anywhere, but they need different names from each other.

There are three rules about sizes:

- **every frame is the same size** as the others;
- **every normal map is the same size** as the others;
- **the normal maps may be smaller than the frames**, by a whole factor `n`, the same on both
  sides.

### Step 2 — preparing the atlas

Add a **FlipbookBaker** node to any working scene and fill its properties:

| property | what it does | how to choose it |
|---|---|---|
| `dir_diffuse` | where the frames are | the path to your images |
| `dir_normal` | where the normal maps are | a folder named unlike the one above |
| `dir_out` | where the atlas folder is written | any folder |
| `atlas_name` | names the atlas folder and its resource | anything unused |
| `tile_px` | size of the tiles | divides the frame, multiple of `4×n` |
| `page_px` | size of the pages | exact multiple of `tile_px + 8×n` |
| `tick_rate` | animation frames per second | free to choose, 24 suggested |

Then press **Bake**. The time it takes grows with the number of frames and with their resolution,
and the editor stays busy until the console says it is done. When the editor is reopened Godot
imports the pages produced, and that wait grows in the same way.

### Step 3 — the node in the scene

Add a **Flipbook** node where you want the animation. It has two properties: the atlas resource
produced by step 2, and the buffering window, that is how many seconds of animation to keep ready
in memory.

---

## Getting the best out of it

### How to draw the animation

This matters more than every setting put together. Two animations of the same length and resolution
can take 30 MB or 1.3 GB: forty times apart, decided only by how much the drawing repeats itself.

The tool saves by recognising the parts that are identical pixel by pixel. So:

- **still areas have to be truly still**: no grain, no noise, no gradients shifting imperceptibly
  across the whole frame;
- **a fixed background with local movement beats a pan** that shifts the whole shot, because there
  nothing repeats any more;
- **the same rules apply to the normal maps**, a portion is stored once only if both the frame and
  its normal map match.

### How large to make the normal maps

Half the width and height of the frames, that is `n` = 2. Below that they visibly blur, above it
they cost a lot and add almost nothing.

Shrinking them too far, below roughly a quarter of the frames, backfires: the footprint starts
growing again instead of falling.

### Tiles and pages

Small tiles find more repetitions, but past a point they stop paying off: between a sixteenth and a
thirty-second of the frame width is the right band.

Pages work well around 4000 pixels a side.

The values below are suggested for `n` = 2. With a different `n` they have to be recomputed.

| frames | `tile_px` | `page_px` |
|---|---|---|
| 1280×720 | 80 | 3840 |
| 1920×1080 | 120 | 4080 |
| 2560×1440 | 160 | 3872 |
| 3840×2160 | 240 | 4096 |
| 7680×4320 | 240 | 4096 |

### Frames per second

`tick_rate` has no suggested value per resolution, but it weighs in proportion: doubling it doubles
both the memory used and the disk work.

### The buffering window

A good rule for its length:

```
seconds = animation length × memory you want to give it ÷ size of the atlas folder
```

If the whole animation fits in memory while leaving room for the system, the full length works
well, especially on slow disks. For animations longer than a few minutes use a narrower window
instead. Keep it above the time of a single frame, and under the animation length. Half a second
usually is a reasonable floor.

### What it costs

There are three costs, and they are almost independent: the time to draw each frame, the memory
used, and the disk read while the animation runs.

| if you increase | drawing | memory | disk |
|---|---|---|---|
| frame resolution | — | ×4 per doubled side | ×4 |
| animation length | — | only with the window on the full length | — |
| frames per second | — | proportional | proportional |
| normal map size | — | grows | grows |
| repetition in the drawing | — | drops a lot | drops a lot |
| buffering window | — | proportional | absorbs the peaks |
| tile size | negligible | little | little |
| game resolution | proportional | — | — |
| area painted on screen | proportional | — | — |
| lighting on | doubles | — | — |

Several animations from the same folder share the memory: a second instance does not double the
footprint, it only adds area to paint.

---

Developed with the help of AI (Claude Code).

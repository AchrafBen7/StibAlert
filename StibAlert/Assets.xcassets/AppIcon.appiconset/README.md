# App Icon — what Apple expects

## ⚠️ CRITICAL: current state

`1024.png` is **actually a JPEG renamed to .png** (verified via `file`).
Apple validates the format at submission and **will reject**. You must
replace it with a real PNG.

## What to provide

ONE file: `1024.png`, **exactly 1024×1024**, **PNG format** (no JPEG
compression), with **no transparency** (Apple rejects alpha channel on
the App Store icon), **no rounded corners** (iOS adds them).

Xcode 14+ auto-generates every smaller size at build time from this
single asset. The Contents.json in this folder uses the modern
"universal" pattern.

## How to regenerate

If you have the source in any format (Photoshop, Figma, Illustrator):

```bash
# From a PNG that has alpha → strip it:
sips -s format png --resampleHeightWidth 1024 1024 source.png \
  --out 1024.png

# Verify it's really a PNG:
file 1024.png
# Should print: PNG image data, 1024 x 1024, 8-bit/color RGB, non-interlaced

# Verify no alpha:
sips -g hasAlpha 1024.png
# Should print: hasAlpha: no
```

Or in Figma/Sketch: export the 1024×1024 frame as PNG, uncheck
"include transparent background", save here.

## Dark / tinted variants (optional, post-launch)

iOS 18+ supports a dark icon and a tinted icon. To add them later:

1. Provide `1024-dark.png` and `1024-tinted.png` (same constraints).
2. Update `Contents.json`:

```json
{
  "images": [
    { "filename": "1024.png",        "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "filename": "1024-dark.png",   "idiom": "universal", "platform": "ios", "size": "1024x1024",
      "appearances": [{ "appearance": "luminosity", "value": "dark" }] },
    { "filename": "1024-tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
      "appearances": [{ "appearance": "luminosity", "value": "tinted" }] }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

## Marketing icon (App Store Connect)

App Store Connect requires a separate **1024×1024 RGB JPEG** for the
store listing. Same image, different format. Upload at submission time
via App Store Connect → App Information → App Icon.

#!/usr/bin/env python3
import json
import sys
import warnings
from PIL import Image
warnings.simplefilter("error", Image.DecompressionBombWarning)
Image.MAX_IMAGE_PIXELS = 40_000_000
try:
    with Image.open(sys.argv[2]) as image:
        count = getattr(image, "n_frames", 1)
        if sys.argv[1] == "info":
            # Validate every frame before publishing, but don't traverse rejected TIFFs.
            if count <= 100:
                for i in range(count):
                    image.seek(i)
                    image.load()
            print(json.dumps({"pages": count, "format": image.format}))
        else:
            image.seek(int(sys.argv[3]))
            image.convert("RGB").save(sys.argv[4], "PNG")
except Exception:
    sys.exit(2)

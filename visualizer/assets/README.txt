This folder is optional. The face in the rain is drawn procedurally in code --
nothing in here is required, and the scene works offline with this folder empty.

TO USE YOUR OWN FACE
  Drop a file named exactly  face.png  in this folder and reload the page.

The loader crops the image to its content, normalizes contrast, and fits it
into the same box the procedural face uses, so any image you swap in lands at
the right size and the right tonal range. Nothing else needs changing.

WHAT WORKS BEST
  - A PNG cutout with a transparent background (best -- the transparency is
    used directly as the silhouette the rain parts around).
  - Otherwise, a portrait on a DARK background. With no alpha channel the
    loader treats "brighter than the backdrop" as the subject.
  - High contrast beats subtlety. The image is resampled down to roughly
    40 glyph cells tall, so soft gradients turn to mush; strong light and
    shadow survive.

To go back to the procedural face, delete or rename face.png.

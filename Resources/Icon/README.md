# MacPad app icon and logo

- `artwork.png` is the picture: a tilted white sheet with a folded corner,
  six lines of colour-coded code and a glowing cursor, on a blue-to-indigo
  glass background. It was generated with an image model (GPT Image 2.6) from
  a written description and is painted edge to edge, with no corners of its
  own. It is MacPad's own artwork.
- `compose-icon.swift` gives the artwork Apple's icon shape: the tile fills
  824 of a 1024 point canvas, its corners are rounded at Apple's proportion,
  a soft shadow sits beneath it and a faint sheen lies over it. It writes every
  size macOS asks for, from 16 to 1024 pixels, plus the two logo files (icon
  and "MacPad" wordmark, one for light pages and one for dark).
- `make-icns.sh` runs the script and packs the sizes into `MacPad.icns` with
  Apple's `iconutil`.
- `MacPad.icns` is what the app bundle ships. `project.yml` copies it into
  `MacPad.app/Contents/Resources` and names it in the bundle's `Info.plist`
  (`CFBundleIconFile`), which is how the Dock and Finder find it.

Everything here is committed, so building MacPad never runs the script. To
change the icon, replace `artwork.png` (any square PNG, 1024 pixels or more)
or edit `compose-icon.swift`, run `./Resources/Icon/make-icns.sh`, and commit
the results together.

# Lumen for Mac

Lumen is a local PDF reader with a cover shelf, pen and highlight tools, typed notes, and persistent bookmarks. Lumen uses the same local preferences as its predecessor, Folio. On upgrade, Continue reading and the Books menu use your existing reading position, bookmarks, and PDF folder.

## Build and open

On a Mac with the macOS 14 SDK or newer and the Xcode command-line tools installed, run these commands from the checkout:

```sh
make build
open Lumen.app
```

On first launch, Lumen creates **Lumen Library** in your Documents folder. Choose **Browse books**, click **Open folder in Finder**, and drop in your PDFs. Their first-page previews appear in the open shelf. You can also choose another folder or press **⌘O** to open a PDF directly. Completed marks save to the original PDF.

Books open one page at a time. Use the page arrows to turn pages, or use the View menu to zoom in and fit the page again. The reading window keeps its size when you turn a page.

Choose **Dark** below the page for black paper and light text, including in scans. Open **Warmth** and drag the slider toward **Warm** for cream paper in Original or warmer lettering in Dark. Click the eye to inspect a figure in its original colors, and click again to restore your settings. Lumen remembers both settings across books and launches. These controls only affect the reading window.

In **Warmth**, turn on **Warm automatically at sunset** and allow approximate location. The page fades to your slider setting over the 30 minutes after local sunset and returns to neutral over the 30 minutes after sunrise. During daylight, drag to preview your evening setting and close the popover to return to neutral. If location is unavailable, the slider still works manually. Lumen keeps a rounded location on your Mac so it can resume the fade while waiting for a fresh fix. Turning off the schedule clears that location.

## Run the checks

```sh
make test
```

The checks use temporary PDFs and isolated preferences. They cover persistence across processes, library setup and updates, and single-page reading in a temporary Mac window.

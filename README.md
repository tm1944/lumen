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

## Run the checks

```sh
make test
```

The checks use temporary PDFs and isolated preferences. They cover persistence across processes, library setup and updates, and single-page reading in a temporary Mac window.

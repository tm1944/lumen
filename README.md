# Lumen for Mac

Lumen is a local PDF reader with a cover shelf, pen and highlight tools, typed notes, and persistent bookmarks. Lumen uses the same local preferences as its predecessor, Folio. On upgrade, Continue reading and the Books menu use your existing reading position, bookmarks, and PDF folder.

## Build and open

On a Mac with the macOS 14 SDK or newer and the Xcode command-line tools installed, run these commands from the checkout:

```sh
make build
open Lumen.app
```

Choose **Browse books** to select a PDF folder, or press **⌘O** to open a PDF directly. Completed marks save to the original PDF.

## Test persistence

```sh
make test
```

The check creates a temporary three-page PDF and a dedicated preferences suite. One process adds marks, bookmarks page 2, and stops on page 3. A second process reopens the PDF, checks the marks and reading position, renames the file, and verifies that a later save preserves an external edit. The test removes its temporary files and preferences on exit.

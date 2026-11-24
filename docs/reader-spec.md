# Lumen for Mac

## Problem Statement

A reader wants to drop a PDF into Documents, open it quickly, and write on it. After a break, they need to pick up where they stopped and find pages they marked earlier. At night, a dark toolbar still leaves a scanned textbook shining white. Changing how the page looks on screen should let the reader use that same book in daylight and share their annotations in its original colors.

## Solution

Lumen opens to a reading room with a Books button and, for returning readers, Continue reading. Books opens a vertically scrolling shelf of first-page previews from the reader's PDF folder. Each book opens one page at a time. The reader can annotate the original PDF, keep bookmarks, switch the whole page to Dark, and adjust warmth manually or let it come on at sunset.

## User Stories

1. As a new reader, I want Lumen to create a PDF folder called **Lumen Library** in my Documents on first launch, so that I know where my books belong.
2. As a reader looking at an empty shelf, I want to open the PDF folder in Finder, so that I can drop in a book and see its cover appear.
3. As a reader with an existing collection, I want to keep my chosen folder when I upgrade, so that I can keep reading without moving my files.
4. As a reader who declines Documents access, I want to choose another folder or open a PDF directly, so that I can still read.
5. As a reader who recognizes a book by its cover, I want a button that opens a vertical book selector with first-page previews, so that I can scroll to the right book.
6. As a reader with a large collection, I want to select a book while other covers are loading, so that the shelf stays usable.
7. As a returning reader, I want Continue reading available at launch, so that I can reopen my last book without browsing.
8. As a reader opening a new book, I want page one to fit in the window, so that I can see the entire page immediately.
9. As a reader turning to a landscape diagram, I want that page to fit inside my existing window, so that I can keep my desktop arranged as I like.
10. As a reader of a long scan, I want Lumen to load pages as I reach them, so that I can start before the rest of the book renders.
11. As a reader studying fine print, I want to zoom and pan on the current page, so that I can inspect details.
12. As a reader marking a passage, I want a text highlighter, so that the relevant words stand out when I return.
13. As a reader working through a diagram, I want to draw a pen stroke with my mouse or trackpad, so that I can mark a specific detail.
14. As a reader recording a thought, I want to attach a typed note to a place on the page, so that its context is clear.
15. As a reader sharing a marked book, I want completed annotations saved into the original PDF, so that they open in Preview without an export step.
16. As a reader interrupted mid-chapter, I want Lumen to remember my reading position across restarts, so that I can resume on the page I left.
17. As a reader who bookmarks an earlier page, I want that bookmark to survive reading further, quitting, and renaming the file, so that I can still jump back to it.
18. As a night reader, I want Dark to turn white paper black and black text white, including in scans, so that the page itself is comfortable to read.
19. As a reader inspecting a color figure, I want a quick look at the original colors and a way back to my reading settings, so that I can interpret the figure correctly.
20. As a reader using light or dark pages, I want a live warmth slider, so that I can choose the paper or lettering tone that suits the room.
21. As a reader who reads through sunset, I want the page to warm automatically to my chosen level, so that I can keep reading through the transition.
22. As a reader reopening a book at night, I want Lumen to remember my appearance and warmth settings, so that each book opens ready to read.
23. As a reader launching Lumen, I want a small bounce while the controls are already usable, so that opening the app feels smooth.
24. As a reader using Reduce Motion, I want the book symbol to appear in its settled position, so that Lumen respects my Mac settings.

## Implementation Decisions

- **Library and launch.** Use Lumen as the release name. Create the default PDF folder on first launch and reuse its existing contents. Preserve an existing folder choice. If access fails, offer Choose folder and Open PDF. Retry default folder creation on request. Watch the active PDF folder, refresh the open book selector after Finder changes, and generate covers on demand. Launch must be independent of folder enumeration and cover rendering.
- **Single-page view.** Start a new book at page one and a known book at its saved reading position. Initially fit a complete page and toolbar on the available screen. Turn pages inside the same window, including after a manual resize. Provide previous and next controls with bounds at the first and last pages. Left and right arrow shortcuts are a proposed convenience.
- **Markup and persistence.** Save each completed highlight, stroke, or note as a standard PDF annotation in the original file. Report a failed save. If another app changes the file, ask the reader to reopen it before adding marks. Keep reading position and deliberate bookmarks independently for each book. Preserve existing readers' bookmarks and reading positions across the product rename.
- **Page appearance.** Original displays authored colors. Dark transforms the whole rendered page, including images and scans. A quick original-color view bypasses Dark and warmth, then restores both. Keep text selection, links and annotation placement usable in either appearance. Apply appearance changes only to the displayed page.
- **Warmth.** Provide a Neutral to Warm slider and an optional **Warm automatically at sunset** switch. In Original, bright paper takes on a warm tone. In Dark, black stays black and light lettering shifts toward ivory and amber. Remember the preference across books and launches.
- **Proposed schedule defaults.** With scheduling off, apply the slider value immediately. With scheduling on, use that value as the evening target. During daylight, preview it while the reader adjusts it and restore neutral when the menu closes. Fade toward the target at local sunset and toward neutral at sunrise. At night, slider changes take effect immediately. Request approximate location when the reader enables scheduling. If unavailable, explain how to enable scheduling and keep manual warmth usable. After wake or relaunch, apply the tone appropriate to the current time.
- **Motion.** Animate the opening book symbol once for about 200 milliseconds. Accept input during the animation. Use the settled symbol with Reduce Motion enabled. Opening the book selector or turning a page does not replay the launch bounce.

## Testing Decisions

Use the running Mac app window as the primary test entry point. Drive the same folder, shelf, page, markup and appearance controls a reader uses. Observe the result in the window, Finder, a new app process, or Preview. Reuse the existing two-process persistence check as a fast regression test. For repeatable schedule tests, control only the clock and location inputs, then observe the visible page tone. Avoid assertions tied to a rendering filter or storage format.

| Scenario | Passing result |
| --- | --- |
| Fresh download and upgrade | On a fresh Mac account, first launch creates Lumen Library in Documents. Dropping two PDFs there updates the open shelf. A pre-existing folder and its books remain usable. Denying access leaves Choose folder and Open PDF usable. Upgrading the prototype preserves the reader's chosen library, bookmarks and reading position. |
| Single-page reading | A new book opens on page one. Turning from portrait to landscape shows one complete page inside the same window. A manual resize survives the next turn. Zoom and pan work, and the first page of a long scan appears before full-document rendering. |
| Annotation round trip | Using a mouse or trackpad, highlight actual text, draw on a figure and attach a typed note. Quit immediately after completing the last mark. Reopen the original in Preview. All three marks appear at the intended locations and the note text is intact. A read-only or externally changed PDF produces a visible save failure and retains its on-disk contents. |
| Bookmark versus reading position | Bookmark page 2, continue to page 3, quit and relaunch. Continue reading opens page 3. Selecting the bookmark opens page 2. Rename the PDF in Finder, reopen it and find the bookmark again. Run the existing two-process check alongside this window-level test. |
| Dark, warmth and original colors | On selectable text, a scan, and a color figure, check both appearances across the slider range. Dark paper stays black, annotations remain legible, and original-color preview restores authored colors. Verify the PDF bytes are identical before and after a display-only session. Add a mark in Dark and confirm Preview shows the original colors plus the mark. |
| Sunset and sunrise | Preview evening warmth during daylight, close the menu, then advance through sunset and sunrise with a page open. Check the gradual transition, night adjustment, wake, relaunch and denied-location fallback. Confirm the evening target survives until the next night. |
| Startup, shelf and pen performance | On the primary Mac with 500 local PDFs, record hardware, dataset and cold and repeat launch times. Use one second to a window accepting Books or Continue reading as the proposed target. Measure time from opening Books to a selectable book, and from opening a large scan to its first visible page. Measure delay between consecutive pen strokes and verify the final stroke survives immediate quit. |
| Launch motion | Observe a single brief bounce, click a control during it, and repeat with Reduce Motion enabled. Verify the click works and the Reduce Motion launch starts in its settled state. |

## Out of Scope

Candidates for later work include searching notes and highlights within a book, a Back action after jumping to an annotation, and editing or searching marks created in other readers. Include an already-annotated PDF in compatibility testing. Whole-page Dark can alter photos and diagrams by design. Original-color preview covers color-sensitive reading.

## Further Notes

The Folio prototype already has the vertical book selector, basic reading, markup, bookmarks and resume. A prior two-process check verified saved annotation types and note contents, independent reading position and bookmarks, rename handling, and protection against overwriting external changes. The full window workflow and startup target remain unverified. The current save path rewrites the PDF after each completed mark, so large-file pen timing should guide any save redesign.

Before release, preserve the existing persistence check in version control, give it a repeatable invocation, and capture a reproducible build and test baseline in the project's first commit.

f.lux informed the warmth and scheduling controls. A page-level color matrix is one implementation candidate that keeps appearance changes local to the book. [f.lux Mac guide](https://justgetflux.com/news/pages/macquickstart/) · [f.lux FAQ](https://justgetflux.com/faq.html) · [Apple Core Image color matrix](https://developer.apple.com/documentation/coreimage/cicolormatrix)

Reader reports informed the later-work candidates. [Finding a note in a long PDF](https://forums.zotero.org/discussion/123805/find-the-exact-page-of-a-note-or-tag-within-a-pdf) · [Returning after an annotation jump](https://forums.zotero.org/discussion/121921/ios-app-feature-request-navigating-back-to-previous-location-in-pdf-after-clicking-on-a-annotation) · [Using existing highlights](https://github.com/koreader/koreader/issues/14994)

# Markup verification

The Mac window check highlights a phrase in selectable text, draws a three-point pen stroke across a figure, and types a note beside it. A second process opens the original PDF and compares the highlight bounds, pen vertices, and note position and text against the fixture. The check runs on a fresh PDF and on one containing an earlier circle annotation.

In Preview, the yellow highlight covered “this passage”, the pen stroke crossed the rectangle, and the note icon appeared beside it. The earlier circle remained below the figure. Reopening the file with PDFKit recovered the note text “Check the diagonal.” In the Lumen window, marking a read-only PDF or a PDF replaced by another app displayed the corresponding save error. Both files retained their exact bytes.

## Consecutive pen strokes

On an M1 MacBook Pro with 8 GB RAM running macOS 15.7.7, an optimized build opened a local copy of a 160-page, 154 MiB synthetic grayscale scan. Five synthetic mouse gestures were delivered to the reading window back to back, with no intentional pause. Each measurement starts at mouse-down and ends when the final mouse-up returns, including the synchronous save.

| Stroke | Time before the next gesture could start |
| --- | ---: |
| 1 | 4,475 ms |
| 2 | 3,957 ms |
| 3 | 3,945 ms |
| 4 | 3,910 ms |
| 5 | 3,933 ms |

The writer exited after stroke five. A fresh process found all five strokes and recovered the final stroke at its expected position. The median delay was 3,945 ms. Rewriting the full PDF on the input thread makes consecutive pen strokes impractical on this file. Save performance needs follow-up work that preserves immediate-quit durability and conflict detection.

import PDFKit
import SwiftUI

struct Failure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure(message) }
    print("PASS: \(message)")
}

func waitFor(_ message: String, until ready: () -> Bool) throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !ready() && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    try expect(ready(), message)
}

func makeBook(at url: URL) throws {
    var portrait = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &portrait, nil) else { throw Failure("Creating PDF") }
    for size in [portrait.size, CGSize(width: 960, height: 400)] {
        var box = CGRect(origin: .zero, size: size)
        let mediaBox = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
        context.fill(box.insetBy(dx: 10, dy: 10))
        context.endPDFPage()
    }
    context.closePDF()
}

func checkFit(_ view: PDFView, pageNumber: Int) throws {
    try waitFor("Page \(pageNumber) is the only visible page and fits entirely in the reader") {
        guard let page = view.currentPage, view.document?.index(for: page) == pageNumber - 1,
              view.visiblePages == [page] else { return false }
        let rect = view.convert(page.bounds(for: view.displayBox), from: page)
        return !rect.isEmpty && view.bounds.insetBy(dx: -1, dy: -1).contains(rect)
    }
}

func run() throws {
    let id = UUID().uuidString
    let suite = "local.lumen.reading." + id
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".pdf")
    guard let defaults = UserDefaults(suiteName: suite) else { throw Failure("Creating preferences") }
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: url)
    }
    try makeBook(at: url)
    let reader = Reader(defaults: defaults)
    let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 900, height: 600),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.toolbar = NSToolbar(identifier: "ReadingTest")
    window.contentView = NSHostingView(rootView: PageView(reader: reader))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    try waitFor("Reader window is ready") { reader.pdfView?.window === window }
    let startingSize = window.frame.size
    reader.open(url)
    guard let view = reader.pdfView else { throw Failure("Missing reading view") }
    try checkFit(view, pageNumber: 1)
    guard let screen = window.screen else { throw Failure("Missing screen") }
    try waitFor("Opening a portrait book sizes the window to the page") { window.frame.width < startingSize.width }
    try expect(screen.visibleFrame.contains(window.frame), "The initial window and toolbar fit on the screen")
    reader.jump(-1)
    try checkFit(view, pageNumber: 1)

    window.setContentSize(NSSize(width: 710, height: 510))
    let resized = window.frame
    reader.jump(1)
    try checkFit(view, pageNumber: 2)
    reader.jump(2)
    try checkFit(view, pageNumber: 2)
    try expect(window.frame == resized, "Turning to a landscape page preserves the manual window size")

    let fit = view.scaleFactor
    view.zoomIn(nil)
    try expect(view.scaleFactor > fit, "Zoom increases the scale of the page")
    guard let content = view.documentView, let scroll = content.enclosingScrollView else { throw Failure("No scroll view") }
    content.scroll(NSPoint(x: content.bounds.maxX, y: 0))
    try expect(scroll.contentView.bounds.minX > 0, "The magnified page can be panned")
    reader.jump(0)
    try checkFit(view, pageNumber: 1)
    reader.jump(1)
    try checkFit(view, pageNumber: 2)

    let reopened = Reader(defaults: defaults)
    reopened.open(url)
    window.contentView = NSHostingView(rootView: PageView(reader: reopened))
    try waitFor("Reopened reader is attached") { reopened.pdfView?.window === window }
    guard let restored = reopened.pdfView else { throw Failure("Missing restored view") }
    try checkFit(restored, pageNumber: 2)
}

_ = NSApplication.shared
do { try run() } catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

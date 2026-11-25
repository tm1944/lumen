import CoreText
import PDFKit
import SwiftUI

struct MarkupFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

let passage = "this passage"
let noteText = "Check the diagonal."
let strokeStart = CGPoint(x: 130, y: 325)
let strokeEnd = CGPoint(x: 255, y: 410)
let notePoint = CGPoint(x: 310, y: 425)

func makeFixture(at url: URL, annotated: Bool, includeScan: Bool = false) throws {
    var box = CGRect(x: 0, y: 0, width: 440, height: 600)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw MarkupFailure("Create fixture") }
    context.beginPDFPage(nil)
    func drawPage(in canvas: CGContext) {
        let line = NSAttributedString(string: "Review this passage today.", attributes: [.font: NSFont.systemFont(ofSize: 20)])
        canvas.textPosition = CGPoint(x: 55, y: 510)
        CTLineDraw(CTLineCreateWithAttributedString(line), canvas)
        canvas.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        canvas.stroke(CGRect(x: 120, y: 315, width: 145, height: 105), width: 2)
        if includeScan {
            canvas.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            canvas.fill(CGRect(x: 120, y: 90, width: 80, height: 60))
        }
    }
    drawPage(in: context)
    if includeScan {
        context.addDestination("text" as CFString, at: CGPoint(x: 0, y: 600))
        context.endPDFPage()
        guard let bitmap = CGContext(data: nil, width: 440, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw MarkupFailure("Create scan") }
        bitmap.setFillColor(CGColor.white)
        bitmap.fill(box)
        bitmap.setFillColor(CGColor.black)
        drawPage(in: bitmap)
        // This blue patch identifies the rendered scan even during a page turn.
        bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 300, y: 90, width: 35, height: 35))
        guard let scan = bitmap.makeImage() else { throw MarkupFailure("Create scan image") }
        context.beginPDFPage(nil)
        context.draw(scan, in: box)
        context.setDestination("text" as CFString, for: CGRect(x: 120, y: 90, width: 80, height: 60))
    }
    context.endPDFPage()
    context.closePDF()

    if annotated {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { throw MarkupFailure("Read fixture") }
        let old = PDFAnnotation(bounds: CGRect(x: 65, y: 215, width: 75, height: 35), forType: .circle, withProperties: nil)
        old.contents = "Earlier review"
        page.addAnnotation(old)
        guard let data = doc.dataRepresentation() else { throw MarkupFailure("Seed annotation") }
        try data.write(to: url, options: .atomic)
    }
}

func gesture(in view: PDFView, page: PDFPage, points: [CGPoint], throughEventQueue: Bool = false) throws {
    guard let window = view.window, let first = points.first, let last = points.last else { throw MarkupFailure("Missing gesture target") }
    func send(_ type: NSEvent.EventType, _ point: CGPoint) throws {
        let location = view.convert(view.convert(point, from: page), to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1) else { throw MarkupFailure("Create mouse event") }
        if throughEventQueue { NSApp.postEvent(event, atStart: false) }
        else { window.sendEvent(event) }
    }
    try send(.mouseMoved, first)
    try send(.leftMouseDown, first)
    for point in points.dropFirst() { try send(.leftMouseDragged, point) }
    try send(.leftMouseUp, last)
    if throughEventQueue {
        // Native PDFKit can track a drag in a nested event loop during mouse-down.
        let deadline = Date(timeIntervalSinceNow: 0.3)
        while let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
            if Date() >= deadline { break }
        }
    }
}

func descendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants(of: $0) }
}

func withOpenPage(_ url: URL, defaults: UserDefaults, schedule: SunsetSchedule? = nil, perform: (Reader, PDFView, PDFPage) throws -> Void) throws {
    _ = NSApplication.shared
    let reader = Reader(defaults: defaults, schedule: schedule)
    reader.open(url)
    let window = NSWindow(contentRect: CGRect(x: 60, y: 60, width: 720, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentMinSize = NSSize(width: 680, height: 480)
    window.contentView = NSHostingView(rootView: ReaderWindow(reader: reader))
    let initialSize = window.frame.size
    window.makeKeyAndOrderFront(nil)
    let deadline = Date(timeIntervalSinceNow: 5)
    func fittedPageIsReady() -> Bool {
        guard let view = reader.pdfView, view.window === window, view.currentPage != nil else { return false }
        return window.frame.size != initialSize && abs(view.bounds.width - window.contentLayoutRect.width) < 1
    }
    while !fittedPageIsReady() && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    defer { window.orderOut(nil) }
    guard fittedPageIsReady(), let view = reader.pdfView, let page = view.currentPage else {
        throw MarkupFailure("Open the PDF in the reading window")
    }
    try perform(reader, view, page)
}

func mark(reader: Reader, view: PDFView, page: PDFPage) throws {
    guard let selected = view.document?.findString(passage, withOptions: []).first else {
        throw MarkupFailure("Find selectable text")
    }
    let text = selected.bounds(for: page)
    reader.tool = .highlight
    try gesture(in: view, page: page, points: [
        CGPoint(x: text.minX + 1, y: text.midY), CGPoint(x: text.maxX - 1, y: text.midY)
    ])
    reader.tool = .pen
    try gesture(in: view, page: page, points: [strokeStart, CGPoint(x: 180, y: 360), strokeEnd])
    reader.tool = .note

    // The note editor runs a nested modal loop until its Save Note button is pressed.
    let enterNote = Timer(timeInterval: 0.02, repeats: true) { timer in
        guard let content = NSApp.modalWindow?.contentView else { return }
        let controls = descendants(of: content)
        guard let editor = controls.compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable }),
              let save = controls.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Save Note" }) else { return }
        timer.invalidate()
        editor.insertText(noteText, replacementRange: editor.selectedRange())
        save.performClick(nil)
    }
    RunLoop.main.add(enterNote, forMode: .modalPanel)
    defer { enterNote.invalidate() }
    try gesture(in: view, page: page, points: [notePoint])
    if let error = reader.error { throw MarkupFailure(error) }
    guard !enterNote.isValid else { throw MarkupFailure("Note editor did not receive its save action") }
}

func verify(_ url: URL, annotated: Bool) throws {
    guard let doc = PDFDocument(url: url), let page = doc.page(at: 0),
          let selected = doc.findString(passage, withOptions: []).first else { throw MarkupFailure("Reopen original PDF") }
    let marks = page.annotations.filter { $0.type != "Popup" }
    guard marks.count == (annotated ? 4 : 3) else { throw MarkupFailure("Unexpected marks: \(marks.map { $0.type ?? "?" })") }
    let wordBox = selected.bounds(for: page)
    guard let highlight = marks.first(where: { $0.type == "Highlight" }),
          highlight.bounds.insetBy(dx: -1, dy: -1).contains(wordBox),
          wordBox.insetBy(dx: -1, dy: -1).contains(highlight.bounds) else { throw MarkupFailure("Highlight placement") }
    guard let ink = marks.first(where: { $0.type == "Ink" }), let path = ink.paths?.first else { throw MarkupFailure("Missing ink stroke") }
    let footprint = path.cgPath.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 2)
    let targets = [strokeStart, CGPoint(x: 180, y: 360), strokeEnd]
    let followsGesture = targets.allSatisfy { point in
        footprint.contains(CGPoint(x: point.x - ink.bounds.minX, y: point.y - ink.bounds.minY))
    }
    let figure = CGRect(x: 120, y: 315, width: 145, height: 105)
    let inkOnPage = footprint.boundingBoxOfPath.offsetBy(dx: ink.bounds.minX, dy: ink.bounds.minY)
    guard followsGesture, figure.contains(inkOnPage) else { throw MarkupFailure("Misplaced ink on the figure") }
    guard let note = marks.first(where: { $0.type == "Text" }), note.contents == noteText,
          abs(note.bounds.minX - notePoint.x) < 1, abs(note.bounds.maxY - notePoint.y) < 1 else { throw MarkupFailure("Note text or position") }
    if annotated {
        guard marks.contains(where: { $0.type == "Circle" && $0.contents == "Earlier review" && $0.bounds == CGRect(x: 65, y: 215, width: 75, height: 35) })
        else { throw MarkupFailure("Original annotation lost or changed") }
    }
    print("PASS: Window-created highlight, ink and note reopen at their intended positions in \(url.lastPathComponent)")
}

func checkFailedSaves(_ url: URL, defaults: UserDefaults) throws {
    let original = try Data(contentsOf: url)
    let files = FileManager.default
    try files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    defer { try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    try withOpenPage(url, defaults: defaults) { reader, view, page in
        reader.tool = .pen
        try gesture(in: view, page: page, points: [strokeStart, strokeEnd])
        guard reader.error?.contains("read-only") == true, try Data(contentsOf: url) == original else {
            throw MarkupFailure("Read-only save did not preserve the file and report the failure")
        }
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var changed = original
        changed.append(contentsOf: "\n% Edited by another reader\n".utf8)
        try changed.write(to: url, options: .atomic)
        reader.error = nil
        try gesture(in: view, page: page, points: [strokeStart, strokeEnd])
        guard reader.error?.contains("changed") == true, try Data(contentsOf: url) == changed else {
            throw MarkupFailure("Conflicting save did not preserve the file and report the failure")
        }
        print("PASS: Window gestures report read-only and external edit failures; both files retain their exact bytes")
    }
}

do {
    alarm(20) // Bound failures in AppKit's modal event loop.
    let args = CommandLine.arguments
    guard args.count == 5, let defaults = UserDefaults(suiteName: args[4]) else { throw MarkupFailure("Expected phase, file, fixture kind and preferences suite") }
    let url = URL(fileURLWithPath: args[2])
    let annotated = args[3] == "annotated"
    switch args[1] {
    case "write":
        try makeFixture(at: url, annotated: annotated)
        try withOpenPage(url, defaults: defaults, perform: mark)
    case "read":
        try verify(url, annotated: annotated)
    case "appearance":
        try checkAppearance(url, defaults: defaults)
    case "sunset":
        try checkSunset(url, defaults: defaults, dark: args[3] == "dark")
    case "reopen-sunset":
        try checkSunsetRelaunch(url, defaults: defaults, dark: args[3] == "dark")
    case "warmth":
        try checkWarmth(url, defaults: defaults)
    case "reopen-warm":
        try checkReopenedWarmth(url, defaults: defaults)
    case "reopen-dark":
        try checkDarkInteractions(url, defaults: defaults)
    case "failures":
        try checkFailedSaves(url, defaults: defaults)
    default: throw MarkupFailure("Unknown phase")
    }
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

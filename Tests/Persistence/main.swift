import AppKit
import PDFKit

struct CheckFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CheckFailure(message) }
    print("PASS: \(message)")
}

func makeBook(at url: URL) throws {
    var bounds = CGRect(x: 0, y: 0, width: 360, height: 500)
    guard let context = CGContext(url as CFURL, mediaBox: &bounds, nil) else {
        throw CheckFailure("Could not create the temporary PDF")
    }
    for _ in 0..<3 {
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 50, y: 400, width: 20, height: 3))
        context.endPDFPage()
    }
    context.closePDF()
}

func markedPage(in reader: Reader) throws -> PDFPage {
    guard let page = reader.book?.document.page(at: 1) else {
        throw CheckFailure(reader.error ?? "Could not open page 2")
    }
    return page
}

func writeSession(_ reader: Reader, at url: URL) throws {
    try makeBook(at: url)
    reader.open(url)
    let page = try markedPage(in: reader)
    reader.recordPage(1)
    reader.toggleBookmark()
    reader.recordPage(2)

    let bounds = CGRect(x: 30, y: 50, width: 40, height: 12)
    let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
    let ink = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
    let path = NSBezierPath()
    path.move(to: .zero)
    path.line(to: CGPoint(x: 30, y: 8))
    ink.add(path)
    let note = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
    note.contents = "Look again."
    for mark in [highlight, ink, note] {
        reader.add([(page, mark)])
        if let error = reader.error { throw CheckFailure(error) }
    }
}

func readSession(_ reader: Reader, at url: URL) throws {
    reader.open(url)
    let annotations = try markedPage(in: reader).annotations
    try check(reader.state.bookmarks == [1] && reader.state.page == 2,
              "A new process restores the bookmark on page 2 and the reading position on page 3")
    // PDFKit adds a companion popup to the note when writing it.
    let types = annotations.compactMap(\.type).filter { $0 != "Popup" }.sorted()
    try check(types == ["Highlight", "Ink", "Text"], "All three marks reopen from the original PDF")
    try check(annotations.contains { $0.type == "Text" && $0.contents == "Look again." },
              "The note retains its text")

    let renamed = url.deletingLastPathComponent().appendingPathComponent("Renamed.pdf")
    try FileManager.default.moveItem(at: url, to: renamed)
    reader.open(renamed)
    if let error = reader.error { throw CheckFailure(error) }
    let page = try markedPage(in: reader)
    try check(reader.state.bookmarks == [1] && reader.state.page == 2,
              "Renaming the PDF preserves the bookmark and reading position")

    var externalEdit = try Data(contentsOf: renamed)
    externalEdit.append(contentsOf: "\n% External edit\n".utf8)
    try externalEdit.write(to: renamed, options: .atomic)
    let newNote = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20),
                                forType: .text, withProperties: nil)
    reader.add([(page, newNote)])
    try check(reader.error != nil, "Adding a mark after an external edit reports a save failure")
    try check(try Data(contentsOf: renamed) == externalEdit, "The external edit survives byte for byte")
}

do {
    let args = CommandLine.arguments
    guard args.count == 4, let defaults = UserDefaults(suiteName: args[3]) else {
        throw CheckFailure("Expected write or read, a temporary directory, and a preferences suite")
    }
    let url = URL(fileURLWithPath: args[2], isDirectory: true).appendingPathComponent("Reading.pdf")
    let reader = Reader(defaults: defaults)
    switch args[1] {
    case "write":
        try writeSession(reader, at: url)
        try check(defaults.synchronize(), "Test preferences reach disk before the writer exits")
    case "read":
        try readSession(reader, at: url)
    default:
        throw CheckFailure("Unknown session: \(args[1])")
    }
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}

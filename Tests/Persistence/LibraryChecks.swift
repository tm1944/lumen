import Foundation

private func waitFor(_ description: String, until ready: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(5)
    while !ready() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    try check(ready(), description)
}

func checkLibrary(in fixture: URL, defaults: UserDefaults) throws {
    let files = FileManager.default
    let documents = fixture.appendingPathComponent("Documents", isDirectory: true)
    let library = documents.appendingPathComponent("Lumen Library", isDirectory: true)
    try files.createDirectory(at: documents, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: documents) }

    let reader = Reader(defaults: defaults)
    reader.prepareLibrary(in: documents)
    try waitFor("First launch creates and selects Lumen Library") { reader.folder == library }
    reader.watchFolder()
    reader.refresh()
    try waitFor("The new shelf is empty") { !reader.scanning && reader.books.isEmpty }

    let first = library.appendingPathComponent("First.pdf")
    let second = library.appendingPathComponent("Second.pdf")
    try makeBook(at: first)
    try makeBook(at: second)
    try waitFor("Both PDFs appear after an external drop into the open library") {
        reader.books.map(\.standardizedFileURL) == [first, second].map(\.standardizedFileURL)
    }
    reader.open(second)
    try check(reader.book?.url == second.resolvingSymlinksInPath(), "Opening a shelf entry uses the original PDF")

    defaults.removeObject(forKey: "folder")
    let existing = Reader(defaults: defaults)
    existing.prepareLibrary(in: documents)
    try waitFor("A fresh reader reuses a populated Lumen Library") { existing.folder == library }
    try check(files.fileExists(atPath: first.path) && files.fileExists(atPath: second.path),
              "Existing PDFs survive library setup")

    defaults.set(fixture, forKey: "folder")
    let custom = Reader(defaults: defaults)
    let unused = documents.appendingPathComponent("Unused")
    custom.prepareLibrary(in: unused)
    try check(custom.folder?.standardizedFileURL.path == fixture.standardizedFileURL.path && !files.fileExists(atPath: unused.path),
              "An existing folder choice takes precedence")

    defaults.removeObject(forKey: "folder")
    let blocked = documents.appendingPathComponent("Blocked")
    try Data().write(to: blocked)
    let failed = Reader(defaults: defaults)
    failed.prepareLibrary(in: blocked)
    try waitFor("A creation failure leaves the folder unset") { !failed.preparingLibrary && failed.folder == nil }
    failed.open(second)
    try check(failed.book != nil, "Direct open works after default folder creation fails")
    try files.removeItem(at: blocked)
    let retry = Reader(defaults: defaults)
    retry.prepareLibrary(in: blocked)
    try check(!retry.preparingLibrary && retry.folder == nil, "Relaunch waits for a requested retry")
    retry.prepareLibrary(in: blocked, retry: true)
    try waitFor("An explicit retry creates the default library") { retry.folder != nil }
}

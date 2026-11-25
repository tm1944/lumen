import AppKit
import Combine
import PDFKit

enum ReadingTool: String, CaseIterable {
    case read = "Read", highlight = "Highlight", pen = "Pen", note = "Note"
    var symbol: String {
        switch self {
        case .read: return "cursorarrow"
        case .highlight: return "highlighter"
        case .pen: return "pencil.tip"
        case .note: return "note.text"
        }
    }
}

struct ReaderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct FileVersion: Equatable {
    let inode: UInt64
    let size: UInt64
    let modified: Date

    init(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let inode = attrs[.systemFileNumber] as? NSNumber,
              let size = attrs[.size] as? NSNumber,
              let date = attrs[.modificationDate] as? Date else {
            throw ReaderError("Could not check the PDF on disk.")
        }
        self.inode = inode.uint64Value
        self.size = size.uint64Value
        self.modified = date
    }
}

final class BookFile {
    let url: URL
    let document: PDFDocument
    private var version: FileVersion

    init(_ input: URL) throws {
        url = input.standardizedFileURL.resolvingSymlinksInPath()
        version = try FileVersion(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else {
            throw ReaderError("This PDF could not be opened. Check that it has pages and is unlocked.")
        }
        guard try FileVersion(url) == version else { throw ReaderError("The PDF changed while opening. Open it again.") }
        document = pdf
    }

    // Add the whole gesture or roll it back, including highlights spanning pages.
    func add(_ marks: [(PDFPage, PDFAnnotation)]) throws {
        guard !marks.isEmpty else { return }
        guard document.allowsCommenting, FileManager.default.isWritableFile(atPath: url.path) else {
            throw ReaderError("This PDF is read-only. Give it write permission to save marks.")
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var saveError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                guard try FileVersion(target) == self.version else {
                    throw ReaderError("This PDF changed in another app. Reopen it before adding marks.")
                }
                for (page, mark) in marks { page.addAnnotation(mark) }
                do {
                    guard let data = self.document.dataRepresentation() else {
                        throw ReaderError("The PDF could not be saved.")
                    }
                    try data.write(to: target, options: .atomic)
                } catch {
                    for (page, mark) in marks { page.removeAnnotation(mark) }
                    throw error
                }
                self.version = try FileVersion(target)
            } catch { saveError = error }
        }
        if let error = saveError ?? coordinationError { throw error }
    }
}

struct ReadingState: Codable {
    var page = 0
    var bookmarks: [Int] = []
}

final class Reader: ObservableObject {
    @Published var folder: URL?
    @Published private(set) var preparingLibrary = false
    @Published private(set) var librarySetupError: String?
    @Published private(set) var books: [URL] = []
    @Published var scanning = false
    @Published var book: BookFile?
    @Published var lastURL: URL?
    @Published var state = ReadingState()
    @Published var tool = ReadingTool.read
    @Published var error: String?
    weak var pdfView: PDFView?
    private let defaults: UserDefaults
    private var stateID = ""
    private var scanID = UUID()
    private var watcher: DispatchSourceFileSystemObject?
    private var refreshWork: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folder = defaults.url(forKey: "folder")
        librarySetupError = defaults.string(forKey: "librarySetupError")
        if let data = defaults.data(forKey: "lastBookmark") {
            var stale = false
            lastURL = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        if lastURL == nil { lastURL = defaults.url(forKey: "lastURL") }
    }

    func prepareLibrary(in documentsDirectory: URL? = nil, retry: Bool = false) {
        guard folder == nil, !preparingLibrary, librarySetupError == nil || retry else { return }
        preparingLibrary = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                let files = FileManager.default
                let documents = try documentsDirectory ?? files.url(for: .documentDirectory, in: .userDomainMask,
                                                                     appropriateFor: nil, create: false)
                let library = documents.appendingPathComponent("Lumen Library", isDirectory: true)
                try files.createDirectory(at: library, withIntermediateDirectories: true)
                // Opening a directory checks access without scanning every book at launch.
                guard let directory = opendir(library.path) else { throw POSIXError(.init(rawValue: errno) ?? .EACCES) }
                closedir(directory)
                return library
            }
            DispatchQueue.main.async {
                self.preparingLibrary = false
                guard self.folder == nil else { return } // A folder chosen during setup wins.
                switch result {
                case .success(let library): self.selectFolder(library)
                case .failure(let error):
                    self.librarySetupError = error.localizedDescription
                    self.defaults.set(error.localizedDescription, forKey: "librarySetupError")
                }
            }
        }
    }

    func selectFolder(_ url: URL) {
        if url == folder {
            // Finder may have replaced the directory at the same path.
            watchFolder()
            refresh()
            return
        }
        books = []
        defaults.removeObject(forKey: "librarySetupError")
        librarySetupError = nil
        defaults.set(url, forKey: "folder")
        folder = url
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use PDF Folder"
        if panel.runModal() == .OK, let url = panel.url {
            selectFolder(url)
        }
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func watchFolder() {
        watcher?.cancel()
        watcher = nil
        guard let folder else { return }
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            self?.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self?.refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        source.setCancelHandler { Darwin.close(fd) }
        watcher = source
        source.resume()
    }

    func refresh() {
        guard let folder else { return }
        let request = UUID()
        scanID = request
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                    .filter { $0.pathExtension.lowercased() == "pdf" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
            DispatchQueue.main.async {
                guard self.scanID == request else { return }
                self.scanning = false
                switch result {
                case .success(let urls): self.books = urls
                case .failure(let failure): self.books = []; self.error = failure.localizedDescription
                }
            }
        }
    }

    func open(_ url: URL) {
        do {
            let next = try BookFile(url)
            let identity = try identityKey(next.url)
            let id = defaults.string(forKey: identity) ?? UUID().uuidString
            let saved = defaults.data(forKey: "state-" + id).flatMap { try? JSONDecoder().decode(ReadingState.self, from: $0) }
            stateID = id
            var restored = saved ?? ReadingState()
            restored.page = min(max(0, restored.page), next.document.pageCount - 1)
            state = restored
            defaults.set(id, forKey: identity)
            tool = .read
            book = next
            remember(next.url)
        } catch { self.error = error.localizedDescription }
    }

    private func identityKey(_ url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let volume = attrs[.systemNumber], let file = attrs[.systemFileNumber] else {
            return "path-" + url.path
        }
        // Include creation time to distinguish a subsequently reused inode.
        return "file-\(volume)-\(file)-\((attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }

    private func remember(_ url: URL) {
        lastURL = url
        defaults.set(url, forKey: "lastURL")
        defaults.set(try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "lastBookmark")
    }

    func add(_ marks: [(PDFPage, PDFAnnotation)]) {
        guard let book, !marks.isEmpty else { return }
        do {
            try book.add(marks)
            // Atomic replacement gives the file a new identity on disk.
            defaults.set(stateID, forKey: try identityKey(book.url))
            remember(book.url)
        } catch { self.error = error.localizedDescription }
        pdfView?.needsDisplay = true
    }

    func recordPage(_ index: Int) {
        guard let book, (0..<book.document.pageCount).contains(index), state.page != index else { return }
        state.page = index
        persist()
    }

    func toggleBookmark() {
        guard book != nil else { return }
        if state.bookmarks.contains(state.page) {
            state.bookmarks.removeAll { $0 == state.page }
        } else {
            state.bookmarks.append(state.page)
            state.bookmarks.sort()
        }
        persist()
    }

    func jump(_ index: Int) {
        guard let page = book?.document.page(at: index) else { return }
        pdfView?.go(to: page)
        recordPage(index)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "state-" + stateID) }
    }
}

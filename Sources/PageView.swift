import CoreImage.CIFilterBuiltins
import PDFKit
import SwiftUI

struct PageView: NSViewRepresentable {
    @ObservedObject var reader: Reader
    func makeNSView(context: Context) -> MarkupView {
        let view = MarkupView()
        view.reader = reader
        view.displayMode = .singlePage
        view.autoScales = true
        view.displaysPageBreaks = false
        reader.pdfView = view
        return view
    }

    func updateNSView(_ view: MarkupView, context: Context) {
        defer { view.setPageAppearance(dark: reader.displaysDarkPage, warmth: reader.previewingOriginal ? 0 : reader.warmth) }
        guard let book = reader.book, view.document !== book.document else { return }
        let page = reader.state.page
        view.restoring = true
        view.document = book.document
        if let target = book.document.page(at: page) {
            view.go(to: target)
            view.autoScales = true
            view.fitWindowOnOpen(to: target)
        }
        view.restoring = false
    }
}

private final class StrokePreview: NSView {
    var points: [CGPoint] = []
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        NSColor.systemIndigo.setStroke()
        path.stroke()
    }
}

final class MarkupView: PDFView {
    weak var reader: Reader?
    var restoring = false
    private var startPage: PDFPage?
    private var points: [CGPoint] = []
    private let preview = StrokePreview()
    private var gesture = ReadingTool.read
    private var initialPage: PDFPage?

    private lazy var darkFilter: CIFilter = CIFilter.colorInvert()
    private var warmthFilter: CIFilter?
    private var appliedWarmth = 0.0

    func setPageAppearance(dark: Bool, warmth: Double) {
        guard let content = documentView else { return }
        var filters = content.contentFilters
        let oldWarmth = warmthFilter
        let warmthChanged = appliedWarmth != warmth
        if warmthChanged {
            appliedWarmth = warmth
            warmthFilter = nil
            if warmth > 0 {
                let matrix = CIFilter.colorMatrix()
                // Scale green and blue after inversion so black always stays black.
                matrix.gVector = CIVector(x: 0, y: 1 - 0.24 * warmth, z: 0, w: 0)
                matrix.bVector = CIVector(x: 0, y: 0, z: 1 - 0.58 * warmth, w: 0)
                warmthFilter = matrix
            }
        }
        let hasDark = filters.contains { $0 as AnyObject === darkFilter }
        let hasWarmth = filters.contains { $0 as AnyObject === warmthFilter }
        guard warmthChanged || hasDark != dark || hasWarmth != (warmthFilter != nil) else { return }
        filters.removeAll { $0 as AnyObject === darkFilter || $0 as AnyObject === oldWarmth }
        if dark { filters.append(darkFilter) }
        if let warmthFilter { filters.append(warmthFilter) }
        content.contentFilters = filters
    }

    func fitWindowOnOpen(to page: PDFPage) {
        initialPage = page
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let page = initialPage, let window, let screen = window.screen,
              bounds.width > 0, bounds.height > 0 else { return }
        initialPage = nil
        // SwiftUI finishes laying out the toolbar and footer before we measure the window.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentPage === page, self.window === window,
                  !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
            let available = screen.visibleFrame
            let chrome = NSSize(width: window.frame.width - self.bounds.width,
                                height: window.frame.height - self.bounds.height)
            let displayed = self.convert(page.bounds(for: self.displayBox), from: page)
            let pageSize = NSSize(width: displayed.width / self.scaleFactor, height: displayed.height / self.scaleFactor)
            guard pageSize.width > 0, pageSize.height > 0 else { return }
            let scale = min(1, (available.width - chrome.width) / pageSize.width,
                            (available.height - chrome.height) / pageSize.height)
            let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size
            let width = min(available.width, max(window.minSize.width, minimum.width, ceil(pageSize.width * scale + chrome.width)))
            let height = min(available.height, max(window.minSize.height, minimum.height, ceil(pageSize.height * scale + chrome.height)))
            let x = max(available.minX, min(window.frame.midX - width / 2, available.maxX - width))
            let y = max(available.minY, min(window.frame.maxY - height, available.maxY - height))
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: self)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    @objc private func pageChanged() {
        guard !restoring, let doc = document, doc === reader?.book?.document, let currentPage else { return }
        let index = doc.index(for: currentPage)
        if reader?.state.page != index, !autoScales { autoScales = true }
        reader?.recordPage(index)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, let reader, reader.tool != .read else { return hit }
        var parent: NSView? = hit
        while let node = parent, node !== self {
            if node is NSScroller { return hit }
            parent = node.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        gesture = reader?.tool ?? .read
        guard gesture != .read else { super.mouseDown(with: event); return }
        let location = convert(event.locationInWindow, from: nil)
        guard let page = page(for: location, nearest: false) else { return }
        startPage = page
        points = [convert(location, to: page)]
        if gesture == .pen {
            preview.frame = bounds
            preview.autoresizingMask = [.width, .height]
            addSubview(preview, positioned: .above, relativeTo: nil)
            preview.points = [location]
            preview.needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard gesture != .read else { super.mouseDragged(with: event); return }
        guard let startPage, let first = points.first else { return }
        let location = convert(event.locationInWindow, from: nil)
        if gesture == .highlight, let end = page(for: location, nearest: true) {
            currentSelection = document?.selection(from: startPage, at: first, to: end, at: convert(location, to: end))
        } else if gesture == .pen, page(for: location, nearest: false) === startPage {
            points.append(convert(location, to: startPage))
            preview.points.append(location)
            preview.needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard gesture != .read else { super.mouseUp(with: event); return }
        defer {
            startPage = nil
            preview.removeFromSuperview()
            points.removeAll()
            gesture = .read
        }
        guard let page = startPage, let first = points.first else { return }
        switch gesture {
        case .highlight:
            mouseDragged(with: event)
            let marks = (currentSelection?.selectionsByLine() ?? []).flatMap { line in
                line.pages.map { page -> (PDFPage, PDFAnnotation) in
                    let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                    annotation.color = .yellow
                    return (page, annotation)
                }
            }
            clearSelection()
            reader?.add(marks)
        case .pen:
            mouseDragged(with: event)
            if points.count == 1 { points.append(CGPoint(x: first.x + 0.1, y: first.y + 0.1)) }
            let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -2, dy: -2)
            let path = NSBezierPath()
            for (index, point) in points.enumerated() {
                let local = CGPoint(x: point.x - box.minX, y: point.y - box.minY)
                if index == 0 { path.move(to: local) } else { path.line(to: local) }
            }
            let ink = PDFAnnotation(bounds: box, forType: .ink, withProperties: nil)
            let border = PDFBorder()
            border.lineWidth = 2
            ink.border = border
            ink.color = NSColor(red: 0.26, green: 0.23, blue: 0.65, alpha: 1)
            ink.add(path)
            reader?.add([(page, ink)])
        case .note:
            writeNote(on: page, at: first)
        case .read: break
        }
    }

    private func writeNote(on page: PDFPage, at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "Add a note"
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        text.isRichText = false
        text.font = .systemFont(ofSize: 14)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Save Note")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let bounds = page.bounds(for: .cropBox)
        let box = CGRect(x: min(max(bounds.minX, point.x), bounds.maxX - 20),
                         y: min(max(bounds.minY, point.y - 20), bounds.maxY - 20), width: 20, height: 20)
        let note = PDFAnnotation(bounds: box, forType: .text, withProperties: nil)
        note.contents = value
        note.iconType = .comment
        note.color = .systemOrange
        reader?.add([(page, note)])
    }
}

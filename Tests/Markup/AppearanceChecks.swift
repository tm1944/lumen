import PDFKit

private func press(_ label: String, in window: NSWindow) throws {
    NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
    guard let content = window.contentView else { throw MarkupFailure("Missing window content") }
    let controls = descendants(of: content)
    for picker in controls.compactMap({ $0 as? NSSegmentedControl }) {
        guard let segment = (0..<picker.segmentCount).first(where: { picker.label(forSegment: $0) == label }) else { continue }
        picker.selectedSegment = segment
        _ = picker.sendAction(picker.action, to: picker.target)
        return
    }

    // SwiftUI also publishes accessibility elements that aren't NSViews.
    func button(in node: AnyObject) -> AnyObject? {
        if node.accessibilityLabel?() == label || node.accessibilityHelp?() == label { return node }
        for child in node.accessibilityChildren?() ?? [] {
            if let found = button(in: child as AnyObject) { return found }
        }
        return nil
    }
    guard let button = button(in: window), button.accessibilityPerformPress?() == true else {
        throw MarkupFailure("Could not press \(label) in the reading window")
    }
}

private func eventually(_ check: () throws -> Void) throws {
    let deadline = Date(timeIntervalSinceNow: 3)
    while true {
        do { try check(); return }
        catch {
            if Date() >= deadline { throw error }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
    }
}

// Sample the composited window so the check includes PDFKit's paper, text and image layers.
private func checkColors(in view: PDFView, dark: Bool, marked: Bool = false) throws {
    guard let window = view.window, let page = view.currentPage else { throw MarkupFailure("Missing page") }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
    try capture.run()
    capture.waitUntilExit()
    guard capture.terminationStatus == 0, let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
        throw MarkupFailure("Capture appearance test window")
    }
    func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
        let point = view.convert(view.convert(CGPoint(x: x, y: y), from: page), to: nil)
        let col = Int(point.x * CGFloat(image.pixelsWide) / window.frame.width)
        let row = Int((window.frame.height - point.y) * CGFloat(image.pixelsHigh) / window.frame.height)
        guard let rgb = image.colorAt(x: col, y: row)?.usingColorSpace(.sRGB) else { throw MarkupFailure("Sample outside window") }
        return rgb
    }
    let paper = try color(90, 400)
    let figure = try color(155, 120)
    func matches(_ value: CGFloat, bright: Bool) -> Bool { bright ? value > 0.85 : value < 0.15 }
    let direction: CGFloat = dark ? -1 : 1
    let redOverGreen = direction * (figure.redComponent - figure.greenComponent)
    let redOverBlue = direction * (figure.redComponent - figure.blueComponent)
    guard matches(paper.redComponent, bright: !dark), matches(paper.greenComponent, bright: !dark),
          matches(paper.blueComponent, bright: !dark), redOverGreen > 0.4, redOverBlue > 0.4
    else { throw MarkupFailure("Wrong page colors (dark=\(dark)): paper \(paper), figure \(figure)") }
    // The fixture has black lettering at this position on both the text page and its scan.
    var letterPixels = 0
    for x in 56..<110 {
        if try matches(color(CGFloat(x), 519).redComponent, bright: dark) { letterPixels += 1 }
    }
    guard letterPixels >= 5 else { throw MarkupFailure("Missing contrasting lettering on the page") }
    if marked {
        // Each of these small regions was monochrome before the gesture.
        let regions = [CGRect(x: 127, y: 509, width: 12, height: 12),
                       CGRect(x: 177, y: 357, width: 6, height: 6),
                       CGRect(x: 311, y: 406, width: 18, height: 18)]
        for region in regions {
            var coloredPixels = 0
            for x in Int(region.minX)..<Int(region.maxX) {
                for y in Int(region.minY)..<Int(region.maxY) {
                    let rgb = try color(CGFloat(x), CGFloat(y))
                    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                    if channels.max()! - channels.min()! > 0.15 { coloredPixels += 1 }
                }
            }
            guard coloredPixels >= 3 else { throw MarkupFailure("Markup missing from visible Dark page at \(region.origin)") }
        }
    }
}

func checkAppearance(_ url: URL, defaults: UserDefaults) throws {
    try makeFixture(at: url, annotated: false, includeScan: true)
    let original = try Data(contentsOf: url)
    try withOpenPage(url, defaults: defaults) { reader, view, _ in
        guard let window = view.window else { throw MarkupFailure("Missing window") }
        try press("Original", in: window)
        try eventually { try checkColors(in: view, dark: false) }
        try press("Dark", in: window)
        try eventually { try checkColors(in: view, dark: true) }
        try press("Show original colors", in: window)
        try eventually { try checkColors(in: view, dark: false) }
        try press("Return to Dark", in: window)
        reader.jump(1)
        try eventually { try checkColors(in: view, dark: true) }
        try press("Show original colors", in: window)
        try eventually { try checkColors(in: view, dark: false) }
    }
    guard try Data(contentsOf: url) == original else { throw MarkupFailure("Display-only session changed PDF bytes") }
    print("PASS: Text page and scan invert, original colors return, PDF bytes remain identical")
}

func checkDarkInteractions(_ url: URL, defaults: UserDefaults) throws {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApp.finishLaunching()
    NSApp.activate(ignoringOtherApps: true)
    try withOpenPage(url, defaults: defaults) { reader, view, scan in
        guard let doc = view.document, doc.index(for: scan) == 1 else { throw MarkupFailure("Reopen on scan") }
        try eventually { try checkColors(in: view, dark: true) }
        let linkPoint = CGPoint(x: 155, y: 120)
        try gesture(in: view, page: scan, points: [linkPoint], throughEventQueue: true)
        guard let page = doc.page(at: 0) else { throw MarkupFailure("Missing link destination") }
        try eventually {
            guard view.currentPage === page else { throw MarkupFailure("Follow link in Dark") }
        }
        guard let words = doc.findString(passage, withOptions: []).first else { throw MarkupFailure("Locate selectable text") }
        let box = words.bounds(for: page)
        try gesture(in: view, page: page, points: [CGPoint(x: box.minX + 1, y: box.midY),
                                                   CGPoint(x: box.maxX - 1, y: box.midY)], throughEventQueue: true)
        guard view.currentSelection?.string == passage else { throw MarkupFailure("Select text in Dark: \(view.currentSelection?.string ?? "none")") }
        view.clearSelection()
        try mark(reader: reader, view: view, page: page)
        try eventually { try checkColors(in: view, dark: true, marked: true) }
        try verify(url, annotated: false)
    }
    print("PASS: Dark survives relaunch during a preview; selection, a link and all three markup tools work in Dark")
}

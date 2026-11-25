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
private func checkColors(in view: PDFView, dark: Bool, marked: Bool = false, warmth: ClosedRange<CGFloat> = -0.05...0.05) throws {
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
    if view.document?.index(for: page) == 1 {
        let patch = try color(317, 107)
        let contrast = patch.blueComponent - patch.redComponent
        guard (dark ? -contrast : contrast) > 0.3 else { throw MarkupFailure("Scan marker is not visible") }
    }
    let paper = try color(90, 400)
    let figure = try color(155, 120)
    func matches(_ value: CGFloat, bright: Bool) -> Bool { bright ? value > 0.85 : value < 0.15 }
    let direction: CGFloat = dark ? -1 : 1
    let redOverGreen = direction * (figure.redComponent - figure.greenComponent)
    let redOverBlue = direction * (figure.redComponent - figure.blueComponent)
    guard matches(paper.redComponent, bright: !dark),
          !dark || (matches(paper.greenComponent, bright: false) && matches(paper.blueComponent, bright: false)),
          redOverGreen > 0.3, redOverBlue > (warmth.upperBound > 0.05 ? 0.05 : 0.4)
    else { throw MarkupFailure("Wrong page colors (dark=\(dark)): paper \(paper), figure \(figure)") }
    // The fixture has black lettering at this position on both the text page and its scan.
    var letters: [NSColor] = []
    for y in 515..<525 {
        for x in 56..<110 {
            let pixel = try color(CGFloat(x), CGFloat(y))
            if matches(pixel.redComponent, bright: dark) { letters.append(pixel) }
        }
    }
    guard letters.count >= 20, let brightest = letters.max(by: { $0.redComponent < $1.redComponent })
    else { throw MarkupFailure("Missing contrasting lettering on the page") }
    let light = dark ? brightest : paper
    let tone = light.redComponent - light.blueComponent
    guard warmth.contains(tone), light.greenComponent >= light.blueComponent - 0.025,
          light.greenComponent <= light.redComponent + 0.025 else {
        throw MarkupFailure("Expected page warmth in \(warmth), measured \(tone) from \(light)")
    }
    if marked {
        // Each of these small regions was monochrome before the gesture.
        let regions = [(CGRect(x: 127, y: 509, width: 12, height: 12), dark),    // highlight
                       (CGRect(x: 177, y: 357, width: 6, height: 6), !dark),     // ink
                       (CGRect(x: 311, y: 406, width: 18, height: 18), dark)]    // note
        for (region, blueDominant) in regions {
            let sign: CGFloat = blueDominant ? -1 : 1
            let background = max(0, sign * (paper.redComponent - paper.blueComponent))
            var coloredPixels = 0
            for x in Int(region.minX)..<Int(region.maxX) {
                for y in Int(region.minY)..<Int(region.maxY) {
                    let rgb = try color(CGFloat(x), CGFloat(y))
                    let chroma = rgb.redComponent - rgb.blueComponent
                    if sign * chroma > background + 0.12 { coloredPixels += 1 }
                }
            }
            guard coloredPixels >= 3 else { throw MarkupFailure("Markup missing from visible page at \(region.origin)") }
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

private let midpointTone: ClosedRange<CGFloat> = 0.06...0.17
private let warmestTone: ClosedRange<CGFloat> = 0.19...0.65

private func dragWarmthSlider(to fraction: Double, checkWhileDragging: () throws -> Void) throws {
    var control: NSSlider?
    try eventually {
        control = NSApp.windows.filter(\.isVisible).compactMap(\.contentView)
            .flatMap(descendants).compactMap { $0 as? NSSlider }.first
        guard control != nil else { throw MarkupFailure("Missing Neutral-to-Warm slider") }
    }
    guard let slider = control, let cell = slider.cell as? NSSliderCell, slider.isContinuous else {
        throw MarkupFailure("Missing live slider")
    }
    let knob = cell.knobRect(flipped: slider.isFlipped)
    let start = NSPoint(x: knob.midX, y: knob.midY)
    let target = NSPoint(x: slider.bounds.minX + fraction * slider.bounds.width, y: knob.midY)
    guard cell.startTracking(at: start, in: slider) else { throw MarkupFailure("Start slider drag") }
    defer { cell.stopTracking(last: start, current: target, in: slider, mouseIsUp: true) }
    _ = cell.continueTracking(last: start, current: target, in: slider)
    guard slider.sendAction(slider.action, to: slider.target) else { throw MarkupFailure("Send continuous slider change") }
    try eventually(checkWhileDragging)
}

func checkWarmth(_ url: URL, defaults: UserDefaults) throws {
    let original = try Data(contentsOf: url)
    try withOpenPage(url, defaults: defaults) { reader, view, _ in
        guard let window = view.window else { throw MarkupFailure("Missing reading window") }
        try press("Original", in: window)
        try press("Warmth", in: window)
        try dragWarmthSlider(to: 0.5) { try checkColors(in: view, dark: false, warmth: midpointTone) }
        try dragWarmthSlider(to: 1) { try checkColors(in: view, dark: false, marked: true, warmth: warmestTone) }
        try press("Warmth", in: window)
        try press("Show original colors", in: window)
        try eventually { try checkColors(in: view, dark: false) }
        try press("Return to warm pages", in: window)
        try eventually { try checkColors(in: view, dark: false, warmth: warmestTone) }
        try press("Dark", in: window)
        try eventually { try checkColors(in: view, dark: true, marked: true, warmth: warmestTone) }
        try press("Show original colors", in: window)
        try eventually { try checkColors(in: view, dark: false) }
        try press("Return to Dark", in: window)
        reader.jump(1)
        try eventually {
            guard let scan = view.document?.page(at: 1), view.visiblePages == [scan], view.currentPage === scan
            else { throw MarkupFailure("Turn to the scanned page") }
            try checkColors(in: view, dark: true, warmth: warmestTone)
        }
        try press("Warmth", in: window)
        try dragWarmthSlider(to: 0) { try checkColors(in: view, dark: true) }
        try dragWarmthSlider(to: 0.5) { try checkColors(in: view, dark: true, warmth: midpointTone) }
        try press("Warmth", in: window)
        try press("Original", in: window)
        try press("Warmth", in: window)
        try dragWarmthSlider(to: 0) { try checkColors(in: view, dark: false) }
        try dragWarmthSlider(to: 0.5) { try checkColors(in: view, dark: false, warmth: midpointTone) }
        try press("Warmth", in: window)

        let other = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: url, to: other)
        defer { try? FileManager.default.removeItem(at: other) }
        reader.open(other)
        try eventually {
            guard view.document === reader.book?.document, reader.book?.url == other.standardizedFileURL.resolvingSymlinksInPath()
            else { throw MarkupFailure("Open second book") }
            try checkColors(in: view, dark: false, warmth: midpointTone)
        }
        guard try Data(contentsOf: other) == original else { throw MarkupFailure("Second PDF changed") }
        reader.open(url)
    }
    guard try Data(contentsOf: url) == original else { throw MarkupFailure("Warmth changed the PDF bytes") }
    print("PASS: Live warmth, original colors, visible markup and identical PDF bytes")
}

func checkReopenedWarmth(_ url: URL, defaults: UserDefaults) throws {
    try withOpenPage(url, defaults: defaults) { _, view, _ in
        try eventually { try checkColors(in: view, dark: false, warmth: midpointTone) }
    }
    print("PASS: A fresh reader process opens the PDF at the chosen intermediate warmth")
}

import Combine
import CoreLocation
import PDFKit

private final class TestSunsetLocation: SunsetLocationSource {
    var result: SunsetLocationUpdate = .denied
    var requests = 0
    var deliver: ((SunsetLocationUpdate) -> Void)?
    func start(_ receive: @escaping (SunsetLocationUpdate) -> Void) {
        requests += 1
        deliver = receive
        receive(result)
    }
    func stop() { deliver = nil }
}

private func date(_ utc: String) -> Date {
    ISO8601DateFormatter().date(from: utc)!
}

private func pressInPopover(_ label: String) throws {
    try eventually {
        for panel in NSApp.windows where panel.isVisible {
            if (try? press(label, in: panel)) != nil { return }
        }
        throw MarkupFailure("Missing popover control: \(label)")
    }
}

// At the equator, 75°W near the March equinox, sunset is about 23:11 UTC
// and sunrise about 11:04 UTC. All clock advances leave the same PDF window open.
private let equator = CLLocationCoordinate2D(latitude: 0, longitude: -75)

func checkSunset(_ url: URL, defaults: UserDefaults, dark: Bool) throws {
    let location = TestSunsetLocation()
    var now = date("2025-03-20T20:00:00Z")
    let ticks = PassthroughSubject<Date, Never>()
    let schedule = SunsetSchedule(defaults: defaults, source: location,
                                  clock: SunsetClock(now: { now }, ticks: ticks.eraseToAnyPublisher()))
    func advance(to utc: String) {
        now = date(utc)
        ticks.send(now)
    }
    try withOpenPage(url, defaults: defaults, schedule: schedule) { reader, view, _ in
        reader.jump(0)
        guard let window = view.window, location.requests == 0 else { throw MarkupFailure("Location requested before opt-in") }
        try press(dark ? "Dark" : "Original", in: window)
        try press("Warmth", in: window)
        try pressInPopover("Warm automatically at sunset")
        try eventually {
            let guidance = NSApp.windows.filter(\.isVisible).contains { window in
                accessibilityElement(in: window) { node in
                    guard node.accessibilityRole?() == .staticText, let object = node as? NSObject,
                          object.responds(to: NSSelectorFromString("accessibilityValue")) else { return false }
                    let text = object.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String
                    return text?.contains("Location Services") == true && text?.contains("manually") == true
                } != nil
            }
            guard guidance else { throw MarkupFailure("Show location settings and manual fallback guidance") }
        }
        try dragWarmthSlider(to: 1) { try checkColors(in: view, dark: dark, checkFigure: false, warmth: warmestTone) }
        location.result = .located(equator)
        try pressInPopover("Retry location")
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false) }
        try dragWarmthSlider(to: 0.5) { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
        try dragWarmthSlider(to: 1) { try checkColors(in: view, dark: dark, checkFigure: false, warmth: warmestTone) }
        try press("Warmth", in: window)
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false) }
        advance(to: "2025-03-20T23:26:00Z")
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
        advance(to: "2025-03-20T23:55:00Z")
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: warmestTone) }
        try press("Warmth", in: window)
        try dragWarmthSlider(to: 0.5) { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
        try press("Warmth", in: window)
        advance(to: "2025-03-21T11:19:00Z")
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: 0.025...0.075) }
        advance(to: "2025-03-21T12:00:00Z")
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false) }
        // Wake after sunset without sending a timer tick.
        now = date("2025-03-22T01:00:00Z")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
    }
    print("PASS: Daytime preview, sunset and sunrise fades, manual fallback, night adjustment and wake (Dark: \(dark))")
}

func checkSunsetRelaunch(_ url: URL, defaults: UserDefaults, dark: Bool) throws {
    let location = TestSunsetLocation()
    location.result = .authorized // The fresh fix hasn't arrived yet.
    var now = date("2025-03-21T23:27:00Z")
    let ticks = PassthroughSubject<Date, Never>()
    let clock = SunsetClock(now: { now }, ticks: ticks.eraseToAnyPublisher())
    let schedule = SunsetSchedule(defaults: defaults, source: location, clock: clock)
    try withOpenPage(url, defaults: defaults, schedule: schedule) { _, view, _ in
        guard let window = view.window, location.requests == 1 else { throw MarkupFailure("Restore enabled schedule") }
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: 0.03...0.08) }
        now = date("2025-03-22T02:00:00Z")
        ticks.send(now)
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
        // At this same UTC instant it is daylight at the new longitude.
        location.deliver?(.located(CLLocationCoordinate2D(latitude: 0, longitude: 150)))
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false) }

        // Tromsø has polar night in December and midnight sun in June.
        location.deliver?(.located(CLLocationCoordinate2D(latitude: 69.65, longitude: 18.96)))
        now = date("2025-12-21T12:00:00Z")
        ticks.send(now)
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false, warmth: midpointTone) }
        now = date("2025-06-21T00:00:00Z")
        ticks.send(now)
        try eventually { try checkColors(in: view, dark: dark, checkFigure: false) }
        try press("Warmth", in: window)
        try pressInPopover("Warm automatically at sunset")
        try dragWarmthSlider(to: 1) { try checkColors(in: view, dark: dark, checkFigure: false, warmth: warmestTone) }
    }
    print("PASS: The schedule and evening target survive relaunch, and disabling restores manual control")
}

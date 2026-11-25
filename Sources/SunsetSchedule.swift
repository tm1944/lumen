import AppKit
import Combine
import CoreLocation

struct SunsetClock {
    var now: () -> Date
    var ticks: AnyPublisher<Date, Never>

    static var system: Self {
        Self(now: Date.init, ticks: Timer.publish(every: 30, tolerance: 3, on: .main, in: .common)
            .autoconnect().eraseToAnyPublisher())
    }
}

enum SunsetLocationUpdate {
    case located(CLLocationCoordinate2D)
    case denied, unavailable
}

protocol SunsetLocationSource {
    func start(_ receive: @escaping (SunsetLocationUpdate) -> Void)
    func stop()
}

final class MacSunsetLocation: NSObject, CLLocationManagerDelegate, SunsetLocationSource {
    private var manager: CLLocationManager?
    private var receive: ((SunsetLocationUpdate) -> Void)?

    func start(_ receive: @escaping (SunsetLocationUpdate) -> Void) {
        stop()
        self.receive = receive
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.distanceFilter = 25_000
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            locationManagerDidChangeAuthorization(manager)
        }
    }

    func stop() {
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil
        receive = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .notDetermined: break
        default: receive?(.denied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let fix = locations.last, fix.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
        receive?(.located(fix.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        let denied = (error as? CLError)?.code == .denied
        receive?(denied ? .denied : .unavailable)
    }
}

// NOAA General Solar Position Calculations, using UTC and east-positive longitude.
// https://gml.noaa.gov/grad/solcalc/solareqns.PDF
private func nightFraction(at date: Date, coordinate: CLLocationCoordinate2D) -> Double {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let minutes = date.timeIntervalSince(utc.startOfDay(for: date)) / 60
    let day = utc.ordinality(of: .day, in: .year, for: date)!
    let yearLength = utc.range(of: .day, in: .year, for: date)!.count
    let radians = Double.pi / 180
    let phase = 2 * Double.pi / Double(yearLength) * (Double(day - 1) + minutes / 1440 - 0.5)
    let equation = 229.18 * (0.000075 + 0.001868 * cos(phase) - 0.032077 * sin(phase)
                             - 0.014615 * cos(2 * phase) - 0.040849 * sin(2 * phase))
    let declination = 0.006918 - 0.399912 * cos(phase) + 0.070257 * sin(phase)
                      - 0.006758 * cos(2 * phase) + 0.000907 * sin(2 * phase)
                      - 0.002697 * cos(3 * phase) + 0.00148 * sin(3 * phase)
    let latitude = coordinate.latitude * radians
    let hourCosine = (cos(90.833 * radians) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
    if hourCosine >= 1 { return 1 } // Polar night
    if hourCosine <= -1 { return 0 } // Midnight sun
    let halfDay = acos(hourCosine) / radians * 4
    let solarMinutes = (minutes + 4 * coordinate.longitude + equation + 1440).truncatingRemainder(dividingBy: 1440)
    // The share of the previous half-hour spent in darkness produces a linear fade
    // after each crossing, including when a short polar night lasts under 30 minutes.
    let fadeMinutes = 30.0
    let start = solarMinutes - fadeMinutes
    func daylightOverlap(noon: Double) -> Double {
        max(0, min(solarMinutes, noon + halfDay) - max(start, noon - halfDay))
    }
    let daylight = daylightOverlap(noon: 720) + daylightOverlap(noon: 720 - 1440)
    return min(1, max(0, 1 - daylight / fadeMinutes))
}

final class SunsetSchedule: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: "sunsetSchedule")
            configure()
        }
    }
    @Published private(set) var fraction: Double?
    @Published private(set) var locationMessage: String?
    private let defaults: UserDefaults
    private let source: SunsetLocationSource
    private let clock: SunsetClock
    private var coordinate: CLLocationCoordinate2D?
    private var subscriptions = Set<AnyCancellable>()

    init(defaults: UserDefaults, source: SunsetLocationSource = MacSunsetLocation(), clock: SunsetClock = .system) {
        self.defaults = defaults
        self.source = source
        self.clock = clock
        enabled = defaults.bool(forKey: "sunsetSchedule")
        if enabled { configure() }
    }

    deinit { source.stop() }

    private func configure() {
        subscriptions.removeAll()
        guard enabled else {
            source.stop()
            coordinate = nil
            fraction = nil
            locationMessage = nil
            return
        }
        clock.ticks.sink { [weak self] in self?.update(at: $0) }.store(in: &subscriptions)
        let wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        let changed = NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
        wake.merge(with: changed).sink { [weak self] _ in
            guard let self else { return }
            self.update(at: self.clock.now())
        }.store(in: &subscriptions)
        requestLocation()
    }

    func requestLocation() {
        guard enabled else { return }
        locationMessage = nil
        source.start { [weak self] event in
            guard let self, self.enabled else { return }
            switch event {
            case .located(let coordinate):
                self.coordinate = coordinate
                self.locationMessage = nil
                self.update(at: self.clock.now())
            case .denied, .unavailable:
                self.coordinate = nil
                self.fraction = nil
                if case .denied = event {
                    self.locationMessage = "Allow Lumen in System Settings → Privacy & Security → Location Services. You can still adjust warmth manually."
                } else {
                    self.locationMessage = "Location is unavailable. Retry when your Mac can determine its location. Manual warmth is available."
                }
            }
        }
    }

    private func update(at date: Date) {
        guard let coordinate else { return }
        let next = nightFraction(at: date, coordinate: coordinate)
        if fraction != next { fraction = next }
    }
}

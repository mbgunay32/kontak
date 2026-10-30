import Foundation
import CoreLocation
import SwiftData
import Observation
import UIKit

/// CLLocationManager needs an NSObject delegate; this forwards to closures.
final class LocationProxy: NSObject, CLLocationManagerDelegate {
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocations?(locations)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Records rides. Two location modes:
/// - watching (idle + auto mode): coarse, battery-friendly updates plus significant-change
///   monitoring, only to notice that a ride has started;
/// - recording: full-accuracy GPS every second.
@Observable
final class RideRecorder {
    enum State { case idle, recording }

    private(set) var state: State = .idle
    private(set) var stats = RideStats()
    private(set) var currentSpeed: Double = 0      // m/s
    private(set) var startDate: Date?
    private(set) var isAutoStarted = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastMessage: String?

    var autoMode: Bool {
        didSet {
            UserDefaults.standard.set(autoMode, forKey: Keys.autoMode)
            if autoMode && !hasAlways { requestPermission() }
            refreshWatching()
        }
    }

    // Tuning
    static let autoStartSpeed = 20 / 3.6          // m/s, sustained for a few seconds
    static let instantStartSpeed = 30 / 3.6       // m/s, one good GPS reading is enough
    static let autoStopDelay: TimeInterval = 5 * 60
    static let minimumRideDistance = 300.0        // m

    private enum Keys { static let autoMode = "autoMode" }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let proxy = LocationProxy()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var lastWatch: CLLocation?
    @ObservationIgnored private var fastSince: Date?
    @ObservationIgnored private var slowSince: Date?
    @ObservationIgnored private var pointsSinceFlush = 0

    init() {
        autoMode = UserDefaults.standard.bool(forKey: Keys.autoMode)
        authorization = manager.authorizationStatus
        manager.delegate = proxy
        manager.activityType = .automotiveNavigation
        proxy.onLocations = { [weak self] locations in self?.handle(locations) }
        proxy.onAuthorization = { [weak self] status in self?.authorizationChanged(status) }
        refreshWatching()
    }

    func attach(context: ModelContext) {
        self.context = context
        recoverUnsavedRide()
    }

    // MARK: - Permission

    var hasAlways: Bool { authorization == .authorizedAlways }
    var canRecord: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    var permissionText: String {
        switch authorization {
        case .authorizedAlways: return "Her Zaman"
        case .authorizedWhenInUse: return "Uygulama Kullanılırken"
        case .denied: return "Reddedildi"
        case .restricted: return "Kısıtlı"
        case .notDetermined: return "Sorulmadı"
        @unknown default: return "Bilinmiyor"
        }
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .denied, .restricted, .authorizedAlways:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            break
        }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        refreshWatching()
    }

    // MARK: - Start / stop

    func start(auto: Bool = false) {
        guard state == .idle else { return }
        guard canRecord else {
            requestPermission()
            return
        }
        stats = RideStats()
        startDate = Date()
        isAutoStarted = auto
        slowSince = nil
        fastSince = nil
        lastMessage = nil
        currentSpeed = 0
        state = .recording

        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        finish(trimAfter: nil)
    }

    private func finish(trimAfter cutoff: Date?) {
        guard state == .recording else { return }
        var final = stats
        if let cutoff {
            let limit = cutoff.timeIntervalSince1970
            final = RideStats.replay(stats.points.filter { $0.t <= limit })
        }
        save(final)
        clearRecoveryFile()

        state = .idle
        stats = RideStats()
        startDate = nil
        isAutoStarted = false
        currentSpeed = 0
        slowSince = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopUpdatingLocation()
        refreshWatching()
    }

    private func save(_ s: RideStats) {
        guard s.distance >= Self.minimumRideDistance else {
            lastMessage = "Sürüş 300 m'den kısa olduğu için kaydedilmedi."
            return
        }
        guard let context else { return }
        context.insert(Ride(stats: s))
        try? context.save()
        lastMessage = "Sürüş kaydedildi: \(Fmt.km(s.distance))"
    }

    // MARK: - Watching for a ride to begin (auto mode)

    private func refreshWatching() {
        guard state == .idle else { return }
        if autoMode && hasAlways {
            manager.startMonitoringSignificantLocationChanges()
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 50
            manager.pausesLocationUpdatesAutomatically = true
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopUpdatingLocation()
        }
    }

    private func handle(_ locations: [CLLocation]) {
        for location in locations {
            switch state {
            case .idle: watch(location)
            case .recording: record(location)
            }
        }
    }

    private func watch(_ loc: CLLocation) {
        guard autoMode, state == .idle else { return }
        guard loc.timestamp.timeIntervalSinceNow > -60,
              loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 200 else { return }

        var speed = loc.speed
        if speed < 0, let prev = lastWatch {
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 2 { speed = loc.distance(from: prev) / dt }
        }
        lastWatch = loc

        if loc.speed >= Self.instantStartSpeed {
            start(auto: true)
            return
        }
        if speed >= Self.autoStartSpeed {
            if let since = fastSince {
                if loc.timestamp.timeIntervalSince(since) >= 5 {
                    start(auto: true)
                }
            } else {
                fastSince = loc.timestamp
            }
        } else {
            fastSince = nil
        }
    }

    // MARK: - Recording

    private func record(_ loc: CLLocation) {
        guard loc.timestamp.timeIntervalSinceNow > -30 else { return }

        if isAutoStarted {
            checkAutoStop(speed: max(loc.speed, 0), at: loc.timestamp)
            if state != .recording { return }
        }

        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else { return }

        let altitude: Double? = (loc.verticalAccuracy > 0 && loc.verticalAccuracy <= 15) ? loc.altitude : nil
        let point = TrackPoint(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            speed: loc.speed,
            alt: altitude,
            t: loc.timestamp.timeIntervalSince1970
        )
        guard stats.add(point) else { return }
        currentSpeed = stats.points.last?.speed ?? 0

        pointsSinceFlush += 1
        if pointsSinceFlush >= 30 { flushRecovery() }
    }

    private func checkAutoStop(speed: Double, at time: Date) {
        if speed < RideStats.movingSpeed {
            if let since = slowSince {
                if time.timeIntervalSince(since) >= Self.autoStopDelay {
                    finish(trimAfter: since)
                }
            } else {
                slowSince = time
            }
        } else {
            slowSince = nil
        }
    }

    // MARK: - Crash recovery

    private var recoveryURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("aktif-surus.json")
    }

    private func flushRecovery() {
        pointsSinceFlush = 0
        let url = recoveryURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(stats.points) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func clearRecoveryFile() {
        pointsSinceFlush = 0
        try? FileManager.default.removeItem(at: recoveryURL)
    }

    /// If the app was killed mid-ride, save what was recorded so far.
    private func recoverUnsavedRide() {
        guard state == .idle,
              let data = try? Data(contentsOf: recoveryURL),
              let points = try? JSONDecoder().decode([TrackPoint].self, from: data) else { return }
        clearRecoveryFile()
        save(RideStats.replay(points))
    }
}

import Foundation
import CoreLocation
import SwiftData
import Observation
import UIKit

/// CLLocationManager needs an NSObject delegate; this forwards to closures.
final class LocationProxy: NSObject, CLLocationManagerDelegate {
    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?
    var onPause: (() -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocations?(locations)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiagLog.shared.log("konum", "hata: \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        DiagLog.shared.log("konum", "iOS konum güncellemelerini duraklattı (hareketsizlik)")
        onPause?()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        DiagLog.shared.log("konum", "iOS konum güncellemelerini sürdürdü")
    }
}

private func kmh(_ mps: Double) -> String { String(format: "%.0f", mps * 3.6) }

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
    private(set) var isPrecise = true

    var autoMode: Bool {
        didSet {
            UserDefaults.standard.set(autoMode, forKey: Keys.autoMode)
            DiagLog.shared.log("ayar", "otomatik kayıt \(autoMode ? "AÇIK" : "KAPALI")")
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

    // Diagnostics counters, summarised in the log every 15 s while recording.
    @ObservationIgnored private var diagAccepted = 0
    @ObservationIgnored private var diagRejectedAccuracy = 0
    @ObservationIgnored private var diagRejectedJump = 0
    @ObservationIgnored private var diagStale = 0
    @ObservationIgnored private var diagLastSummary = Date()
    @ObservationIgnored private var diagLastAccuracy: Double = -1
    @ObservationIgnored private var watchMode = "kapalı"
    @ObservationIgnored private var watchPaused = false
    @ObservationIgnored private var lastLocationAt: Date?
    @ObservationIgnored private var lastAcceptedAt: Date?
    @ObservationIgnored private var watchdog: Timer?

    private let log = DiagLog.shared

    init() {
        autoMode = UserDefaults.standard.bool(forKey: Keys.autoMode)
        authorization = manager.authorizationStatus
        manager.delegate = proxy
        manager.activityType = .automotiveNavigation
        proxy.onLocations = { [weak self] locations in self?.handle(locations) }
        proxy.onAuthorization = { [weak self] status in self?.authorizationChanged(status) }
        proxy.onPause = { [weak self] in
            guard let self, self.state == .idle else { return }
            self.watchPaused = true
        }
        isPrecise = manager.accuracyAuthorization == .fullAccuracy

        let appState: String
        switch UIApplication.shared.applicationState {
        case .active: appState = "ön planda"
        case .inactive: appState = "geçişte"
        case .background: appState = "ARKA PLANDA (iOS tarafından başlatıldı)"
        @unknown default: appState = "?"
        }
        log.log("uygulama", "açıldı · \(appState) · izin=\(permissionText) · otomatik=\(autoMode ? "açık" : "kapalı")")
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
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
        log.log("izin", "konum izni: \(permissionText) · hassas konum: \(manager.accuracyAuthorization == .fullAccuracy ? "açık" : "KAPALI")")
        refreshWatching()
    }

    // MARK: - Start / stop

    func start(auto: Bool = false) {
        guard state == .idle else { return }
        guard canRecord else {
            log.log("kayıt", "başlatılamadı: konum izni yok (\(permissionText))")
            requestPermission()
            return
        }
        log.log("kayıt", "BAŞLADI · \(auto ? "otomatik" : "elle")")
        diagAccepted = 0; diagRejectedAccuracy = 0; diagRejectedJump = 0; diagStale = 0
        diagLastSummary = Date()
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
        watchPaused = false
        lastLocationAt = Date()
        lastAcceptedAt = nil
        manager.startUpdatingLocation()

        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkWatchdog()
        }
    }

    /// Ends an auto-started ride if GPS has gone completely silent (e.g. underground car park),
    /// since the normal auto-stop only runs when a location arrives.
    private func checkWatchdog() {
        guard state == .recording, isAutoStarted,
              let last = lastLocationAt,
              Date().timeIntervalSince(last) >= Self.autoStopDelay * 2 else { return }
        log.log("kayıt", "10 dk hiç konum gelmedi → otomatik bitiriliyor")
        finish(trimAfter: lastAcceptedAt ?? last)
    }

    func stop() {
        log.log("kayıt", "elle bitirildi")
        finish(trimAfter: nil)
    }

    private func finish(trimAfter cutoff: Date?) {
        guard state == .recording else { return }
        var final = stats
        if let cutoff {
            let limit = cutoff.timeIntervalSince1970
            final = RideStats.replay(stats.points.filter { $0.t <= limit })
            log.log("kayıt", "sondaki bekleme kesildi: \(stats.points.count - final.points.count) nokta çıkarıldı")
        }
        log.log("kayıt", "BİTTİ · mesafe=\(Int(final.distance)) m · nokta=\(final.points.count) · hareket=\(Int(final.movingTime)) s · durma=\(Int(final.stoppedTime)) s · azami=\(kmh(final.maxSpeed)) km/h · sert fren=\(final.hardBrakes) · sert hızlanma=\(final.hardAccels) · durak=\(final.stopCount)")
        save(final)
        clearRecoveryFile()

        state = .idle
        stats = RideStats()
        startDate = nil
        isAutoStarted = false
        currentSpeed = 0
        slowSince = nil
        watchdog?.invalidate()
        watchdog = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopUpdatingLocation()
        refreshWatching()
    }

    private func save(_ s: RideStats) {
        guard s.distance >= Self.minimumRideDistance else {
            lastMessage = "Sürüş 300 m'den kısa olduğu için kaydedilmedi."
            log.log("kayıt", "kaydedilmedi: \(Int(s.distance)) m < 300 m")
            return
        }
        guard let context else {
            log.log("kayıt", "HATA: veritabanı bağlı değil, sürüş kaydedilemedi")
            return
        }
        context.insert(Ride(stats: s))
        do {
            try context.save()
            log.log("kayıt", "veritabanına kaydedildi")
        } catch {
            log.log("kayıt", "HATA: kaydedilemedi: \(error.localizedDescription)")
        }
        lastMessage = "Sürüş kaydedildi: \(Fmt.km(s.distance))"
    }

    // MARK: - Watching for a ride to begin (auto mode)

    private func refreshWatching() {
        guard state == .idle else { return }
        let mode = autoMode && hasAlways ? "açık" : (autoMode ? "beklemede (izin 'Her Zaman' değil)" : "kapalı")
        if mode != watchMode {
            watchMode = mode
            log.log("izleme", "otomatik başlatma izlemesi: \(mode)")
        }
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
        // After iOS paused the coarse updates, the next location comes from
        // significant-change monitoring. Turn the coarse updates back on.
        if state == .idle && watchPaused && autoMode && hasAlways {
            watchPaused = false
            log.log("izleme", "önemli konum değişikliği uyandırdı · izleme yeniden başlatıldı")
            manager.startUpdatingLocation()
        }
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
              loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 200 else {
            log.log("izleme", "nokta atlandı · doğruluk=\(Int(loc.horizontalAccuracy)) m · yaş=\(Int(-loc.timestamp.timeIntervalSinceNow)) s")
            return
        }

        var speed = loc.speed
        var source = "gps"
        if speed < 0, let prev = lastWatch {
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 2 {
                speed = loc.distance(from: prev) / dt
                source = "hesap"
            }
        }
        lastWatch = loc

        let base = "hız=\(speed >= 0 ? kmh(speed) : "?") km/h (\(source)) · doğruluk=\(Int(loc.horizontalAccuracy)) m"
        if loc.speed >= Self.instantStartSpeed {
            log.log("izleme", "\(base) → hemen başlat")
            start(auto: true)
            return
        }
        if speed >= Self.autoStartSpeed {
            if let since = fastSince {
                if loc.timestamp.timeIntervalSince(since) >= 5 {
                    log.log("izleme", "\(base) → 5 sn hızlı, başlat")
                    start(auto: true)
                } else {
                    log.log("izleme", "\(base) → aday")
                }
            } else {
                fastSince = loc.timestamp
                log.log("izleme", "\(base) → aday (ilk)")
            }
        } else {
            if fastSince != nil { log.log("izleme", "\(base) → aday iptal") }
            fastSince = nil
        }
    }

    // MARK: - Recording

    private func record(_ loc: CLLocation) {
        defer { logSummaryIfDue() }
        guard loc.timestamp.timeIntervalSinceNow > -30 else {
            diagStale += 1
            return
        }
        diagLastAccuracy = loc.horizontalAccuracy
        lastLocationAt = Date()

        if isAutoStarted {
            checkAutoStop(speed: max(loc.speed, 0), at: loc.timestamp)
            if state != .recording { return }
        }

        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else {
            diagRejectedAccuracy += 1
            return
        }

        let altitude: Double? = (loc.verticalAccuracy > 0 && loc.verticalAccuracy <= 15) ? loc.altitude : nil
        let point = TrackPoint(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            speed: loc.speed,
            alt: altitude,
            t: loc.timestamp.timeIntervalSince1970
        )
        let prevSpeed = stats.points.last?.speed ?? 0
        let brakesBefore = stats.hardBrakes, accelsBefore = stats.hardAccels, stopsBefore = stats.stopCount
        guard stats.add(point) else {
            diagRejectedJump += 1
            return
        }
        diagAccepted += 1
        lastAcceptedAt = loc.timestamp
        currentSpeed = stats.points.last?.speed ?? 0

        if stats.hardBrakes > brakesBefore {
            log.log("olay", "SERT FREN · \(kmh(prevSpeed)) → \(kmh(currentSpeed)) km/h")
        }
        if stats.hardAccels > accelsBefore {
            log.log("olay", "SERT HIZLANMA · \(kmh(prevSpeed)) → \(kmh(currentSpeed)) km/h")
        }
        if stats.stopCount > stopsBefore {
            log.log("olay", "durak sayıldı (\(stats.stopCount). durak)")
        }

        pointsSinceFlush += 1
        if pointsSinceFlush >= 30 { flushRecovery() }
    }

    private func checkAutoStop(speed: Double, at time: Date) {
        if speed < RideStats.movingSpeed {
            if let since = slowSince {
                if time.timeIntervalSince(since) >= Self.autoStopDelay {
                    log.log("kayıt", "5 dk hareketsiz → otomatik bitiriliyor")
                    finish(trimAfter: since)
                }
            } else {
                slowSince = time
                log.log("kayıt", "durdu · 5 dk böyle kalırsa kayıt biter")
            }
        } else {
            if let since = slowSince {
                log.log("kayıt", "tekrar hareket · \(Int(time.timeIntervalSince(since))) sn beklendi")
            }
            slowSince = nil
        }
    }

    private func logSummaryIfDue() {
        guard state == .recording, Date().timeIntervalSince(diagLastSummary) >= 15 else { return }
        diagLastSummary = Date()
        log.log("kayıt", "özet · hız=\(kmh(currentSpeed)) km/h · doğruluk=\(Int(diagLastAccuracy)) m · mesafe=\(Int(stats.distance)) m · kabul=\(diagAccepted) · red(doğruluk)=\(diagRejectedAccuracy) · red(sıçrama)=\(diagRejectedJump) · eski=\(diagStale)")
        diagAccepted = 0; diagRejectedAccuracy = 0; diagRejectedJump = 0; diagStale = 0
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
        log.log("kurtarma", "yarım kalan sürüş bulundu: \(points.count) nokta, kurtarılıyor")
        save(RideStats.replay(points))
    }
}

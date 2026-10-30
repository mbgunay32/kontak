import Foundation

/// Accumulates a ride from GPS points. Pure value type so it can be replayed
/// (crash recovery, trimming the idle tail of an auto-stopped ride).
struct RideStats {
    private(set) var points: [TrackPoint] = []
    private(set) var distance: Double = 0          // m, counted only while moving
    private(set) var movingTime: Double = 0        // s
    private(set) var stoppedTime: Double = 0       // s
    private(set) var maxSpeed: Double = 0          // m/s
    private(set) var elevationGain: Double = 0     // m
    private(set) var stopCount = 0
    private(set) var hardBrakes = 0
    private(set) var hardAccels = 0
    private(set) var bandDistances = Array(repeating: 0.0, count: SpeedBands.count)

    // Tuning
    static let movingSpeed = 1.4          // m/s (~5 km/h)
    static let maxPlausibleSpeed = 75.0   // m/s (~270 km/h) – anything faster is a GPS jump
    static let stopMinDuration = 15.0     // s standing still to count as a stop
    static let hardBrakeDecel = 3.5       // m/s² (~0.36 g)
    static let hardAccel = 3.0            // m/s²
    static let elevationStep = 3.0        // m, ignore altitude noise below this

    private var stoppedSince: TimeInterval?
    private var stopCounted = false
    private var lastEventT: TimeInterval = 0
    private var altitudeRef: Double?

    var startT: TimeInterval? { points.first?.t }
    var endT: TimeInterval? { points.last?.t }
    var avgSpeed: Double { movingTime > 0 ? distance / movingTime : 0 }

    /// Adds a point. Returns false when the point was rejected.
    @discardableResult
    mutating func add(_ raw: TrackPoint) -> Bool {
        guard let prev = points.last else {
            var p = raw
            p.speed = max(raw.speed, 0)
            points.append(p)
            altitudeRef = p.alt
            return true
        }

        let dt = raw.t - prev.t
        guard dt >= 0.2 else { return false }

        let d = prev.distance(to: raw)
        let implied = d / dt
        guard implied <= Self.maxPlausibleSpeed else { return false }

        var p = raw
        p.speed = raw.speed >= 0 ? min(raw.speed, Self.maxPlausibleSpeed) : implied
        let v = p.speed

        maxSpeed = max(maxSpeed, v)

        if v >= Self.movingSpeed {
            movingTime += dt
            distance += d
            bandDistances[SpeedBands.index(forSpeed: v)] += d
            stoppedSince = nil
            stopCounted = false
        } else {
            stoppedTime += dt
            if stoppedSince == nil { stoppedSince = prev.t }
            if !stopCounted, let since = stoppedSince, p.t - since >= Self.stopMinDuration, distance > 50 {
                stopCount += 1
                stopCounted = true
            }
        }

        // Hard braking / acceleration from consecutive GPS speeds.
        if dt <= 3, p.t - lastEventT > 4 {
            let a = (v - prev.speed) / dt
            if a <= -Self.hardBrakeDecel && prev.speed > 5 {
                hardBrakes += 1
                lastEventT = p.t
            } else if a >= Self.hardAccel {
                hardAccels += 1
                lastEventT = p.t
            }
        }

        // Elevation gain with a dead band against altitude noise.
        if let alt = p.alt {
            if let ref = altitudeRef {
                if alt - ref >= Self.elevationStep {
                    elevationGain += alt - ref
                    altitudeRef = alt
                } else if ref - alt >= Self.elevationStep {
                    altitudeRef = alt
                }
            } else {
                altitudeRef = alt
            }
        }

        points.append(p)
        return true
    }

    static func replay(_ points: [TrackPoint]) -> RideStats {
        var s = RideStats()
        for p in points { s.add(p) }
        return s
    }
}

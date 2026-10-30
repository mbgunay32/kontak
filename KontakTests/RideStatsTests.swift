import XCTest
@testable import Kontak

/// Synthetic rides heading north from a fixed point, one fix per second.
private struct FakeRide {
    private(set) var points: [TrackPoint] = []
    private var lat = 41.0
    private var t = 1_800_000_000.0
    private let lon = 29.0
    private let metersPerDegree = 111_195.0

    /// Ride `seconds` at a constant speed (m/s).
    mutating func cruise(_ speed: Double, seconds: Int) {
        for _ in 0..<seconds { step(speed) }
    }

    /// One second at `speed`.
    mutating func step(_ speed: Double) {
        t += 1
        lat += speed / metersPerDegree
        points.append(TrackPoint(lat: lat, lon: lon, speed: speed, alt: nil, t: t))
    }

    mutating func start(speed: Double = 0) {
        points.append(TrackPoint(lat: lat, lon: lon, speed: speed, alt: nil, t: t))
    }
}

final class RideStatsTests: XCTestCase {

    func testSpeedBandIndex() {
        XCTAssertEqual(SpeedBands.index(forKmh: 0), 0)
        XCTAssertEqual(SpeedBands.index(forKmh: 29.9), 0)
        XCTAssertEqual(SpeedBands.index(forKmh: 30), 1)
        XCTAssertEqual(SpeedBands.index(forKmh: 89), 2)
        XCTAssertEqual(SpeedBands.index(forKmh: 119), 3)
        XCTAssertEqual(SpeedBands.index(forKmh: 120), 4)
        XCTAssertEqual(SpeedBands.index(forKmh: 200), 4)
        XCTAssertEqual(SpeedBands.label(0), "0–30")
        XCTAssertEqual(SpeedBands.label(4), "120+")
    }

    func testDistanceAndBandsAtConstantSpeed() {
        var ride = FakeRide()
        ride.start(speed: 10)
        ride.cruise(10, seconds: 120)          // 36 km/h for 2 min ≈ 1200 m
        let s = RideStats.replay(ride.points)

        XCTAssertEqual(s.distance, 1200, accuracy: 15)
        XCTAssertEqual(s.bandDistances[1], s.distance, accuracy: 15, "all distance should be in 30–60 km/h")
        XCTAssertEqual(s.maxSpeed, 10, accuracy: 0.01)
        XCTAssertEqual(s.movingTime, 120, accuracy: 1)
        XCTAssertEqual(s.hardBrakes, 0)
        XCTAssertEqual(s.hardAccels, 0)
    }

    func testDistanceSplitsAcrossBands() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(5, seconds: 60)            // 18 km/h → band 0, ~300 m
        for v in stride(from: 5.0, through: 25.0, by: 2.0) { ride.step(v) }  // gentle ramp
        ride.cruise(25, seconds: 60)           // 90 km/h → band 3, ~1500 m
        let s = RideStats.replay(ride.points)

        XCTAssertEqual(s.bandDistances[0], 300, accuracy: 20)
        XCTAssertEqual(s.bandDistances[3], 1500 + 25, accuracy: 30)
        XCTAssertEqual(s.bandDistances.reduce(0, +), s.distance, accuracy: 0.001)
    }

    func testHardBrakeCountedOnce() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(16, seconds: 30)           // ~58 km/h
        ride.step(11)                          // −5 m/s² → hard brake
        ride.step(6)                           // still braking, within cooldown
        ride.cruise(6, seconds: 10)
        let s = RideStats.replay(ride.points)
        XCTAssertEqual(s.hardBrakes, 1)
    }

    func testGentleBrakeNotCounted() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(16, seconds: 30)
        for v in stride(from: 14.0, through: 2.0, by: -2.0) { ride.step(v) }  // −2 m/s²
        let s = RideStats.replay(ride.points)
        XCTAssertEqual(s.hardBrakes, 0)
    }

    func testHardAcceleration() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(2, seconds: 5)
        ride.step(6)                           // +4 m/s²
        ride.cruise(8, seconds: 10)
        let s = RideStats.replay(ride.points)
        XCTAssertEqual(s.hardAccels, 1)
    }

    func testStopCountedOnlyAfter15Seconds() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(10, seconds: 30)
        ride.cruise(0, seconds: 10)            // short wait: not a stop
        ride.cruise(10, seconds: 30)
        ride.cruise(0, seconds: 25)            // traffic light: a stop
        ride.cruise(10, seconds: 30)
        let s = RideStats.replay(ride.points)
        XCTAssertEqual(s.stopCount, 1)
        XCTAssertEqual(s.stoppedTime, 35, accuracy: 2)
    }

    func testGpsJumpRejected() {
        var stats = RideStats()
        let t0 = 1_800_000_000.0
        XCTAssertTrue(stats.add(TrackPoint(lat: 41.0, lon: 29.0, speed: 10, alt: nil, t: t0)))
        XCTAssertTrue(stats.add(TrackPoint(lat: 41.00009, lon: 29.0, speed: 10, alt: nil, t: t0 + 1)))
        // 1 km in one second
        XCTAssertFalse(stats.add(TrackPoint(lat: 41.01, lon: 29.0, speed: 10, alt: nil, t: t0 + 2)))
        XCTAssertLessThan(stats.distance, 20)
    }

    func testMissingSpeedIsDerivedFromDistance() {
        var stats = RideStats()
        let t0 = 1_800_000_000.0
        stats.add(TrackPoint(lat: 41.0, lon: 29.0, speed: -1, alt: nil, t: t0))
        stats.add(TrackPoint(lat: 41.0 + 20 / 111_195.0, lon: 29.0, speed: -1, alt: nil, t: t0 + 1))
        XCTAssertEqual(stats.points.last?.speed ?? 0, 20, accuracy: 0.5)
        XCTAssertEqual(stats.bandDistances[2], 20, accuracy: 0.5) // 72 km/h
    }

    func testElevationIgnoresSmallNoise() {
        var stats = RideStats()
        let t0 = 1_800_000_000.0
        let alts: [Double] = [100, 101, 99, 102, 100, 105, 110, 108, 115]
        for (i, a) in alts.enumerated() {
            stats.add(TrackPoint(lat: 41.0 + Double(i) * 10 / 111_195.0, lon: 29.0, speed: 10, alt: a, t: t0 + Double(i)))
        }
        // Real climb is 100 → 115 with one small dip; noise under 3 m is ignored.
        XCTAssertEqual(stats.elevationGain, 15, accuracy: 3)
    }

    func testRouteSegmentsFollowBands() {
        var ride = FakeRide()
        ride.start()
        ride.cruise(5, seconds: 30)            // band 0
        ride.cruise(20, seconds: 30)           // band 2
        let segments = RouteBuilder.segments(from: RideStats.replay(ride.points).points)
        XCTAssertEqual(segments.first?.band, 0)
        XCTAssertEqual(segments.last?.band, 2)
        XCTAssertTrue(segments.allSatisfy { $0.coordinates.count >= 2 })
    }
}

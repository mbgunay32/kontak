import Foundation
import CoreLocation

/// One accepted GPS fix. `speed` is already cleaned (m/s, never negative).
struct TrackPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var speed: Double
    var alt: Double?
    var t: TimeInterval   // seconds since 1970

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func distance(to other: TrackPoint) -> Double {
        let r = 6_371_000.0
        let p1 = lat * .pi / 180, p2 = other.lat * .pi / 180
        let dp = (other.lat - lat) * .pi / 180
        let dl = (other.lon - lon) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

import Foundation
import CoreLocation

/// A stretch of the route ridden within one speed band.
struct RouteSegment: Identifiable {
    let id: Int
    let band: Int
    let coordinates: [CLLocationCoordinate2D]
}

enum RouteBuilder {
    static func segments(from points: [TrackPoint], maxPoints: Int = 4000) -> [RouteSegment] {
        guard points.count > 1 else { return [] }

        let pts: [TrackPoint]
        if points.count > maxPoints {
            let step = Int((Double(points.count) / Double(maxPoints)).rounded(.up))
            var sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
            if let last = points.last, sampled.last != last { sampled.append(last) }
            pts = sampled
        } else {
            pts = points
        }

        // Smooth speeds a little so the colors don't flicker on every GPS wobble.
        let raw = pts.map(\.speed)
        var speeds = raw
        let w = 2
        for i in raw.indices {
            let lo = max(0, i - w), hi = min(raw.count - 1, i + w)
            speeds[i] = raw[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }

        var result: [RouteSegment] = []
        var band = SpeedBands.index(forSpeed: speeds[1])
        var coords = [pts[0].coordinate]
        for i in 1..<pts.count {
            coords.append(pts[i].coordinate)
            let b = SpeedBands.index(forSpeed: speeds[i])
            if b != band {
                result.append(RouteSegment(id: result.count, band: band, coordinates: coords))
                coords = [pts[i].coordinate]
                band = b
            }
        }
        if coords.count > 1 {
            result.append(RouteSegment(id: result.count, band: band, coordinates: coords))
        }
        return result
    }
}

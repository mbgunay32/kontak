import Foundation
import SwiftData

@Model
final class Ride {
    var start: Date
    var end: Date
    var distance: Double
    var movingTime: Double
    var stoppedTime: Double
    var maxSpeed: Double
    var elevationGain: Double
    var stopCount: Int
    var hardBrakes: Int
    var hardAccels: Int
    var bandDistances: [Double]
    @Attribute(.externalStorage) var pointsData: Data

    init(stats: RideStats) {
        start = Date(timeIntervalSince1970: stats.startT ?? Date().timeIntervalSince1970)
        end = Date(timeIntervalSince1970: stats.endT ?? Date().timeIntervalSince1970)
        distance = stats.distance
        movingTime = stats.movingTime
        stoppedTime = stats.stoppedTime
        maxSpeed = stats.maxSpeed
        elevationGain = stats.elevationGain
        stopCount = stats.stopCount
        hardBrakes = stats.hardBrakes
        hardAccels = stats.hardAccels
        bandDistances = stats.bandDistances
        pointsData = (try? JSONEncoder().encode(stats.points)) ?? Data()
    }

    var points: [TrackPoint] {
        (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? []
    }

    var totalTime: Double { end.timeIntervalSince(start) }
    var avgSpeed: Double { movingTime > 0 ? distance / movingTime : 0 }

    func bandDistance(_ i: Int) -> Double {
        i < bandDistances.count ? bandDistances[i] : 0
    }
}

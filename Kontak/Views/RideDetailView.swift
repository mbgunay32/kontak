import SwiftUI
import MapKit

struct RideDetailView: View {
    let ride: Ride
    private let segments: [RouteSegment]
    @State private var showCard = false

    init(ride: Ride) {
        self.ride = ride
        self.segments = RouteBuilder.segments(from: ride.points)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RouteMap(segments: segments)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                LazyVGrid(columns: columns, spacing: 10) {
                    StatTile(title: "Mesafe", value: Fmt.km(ride.distance))
                    StatTile(title: "Toplam süre", value: Fmt.duration(ride.totalTime))
                    StatTile(title: "Hareket", value: Fmt.duration(ride.movingTime))
                    StatTile(title: "Ort. hız", value: Fmt.speed(ride.avgSpeed))
                    StatTile(title: "Azami", value: Fmt.speed(ride.maxSpeed))
                    StatTile(title: "Tırmanış", value: "\(Int(ride.elevationGain)) m")
                    StatTile(title: "Durak", value: "\(ride.stopCount)")
                    StatTile(title: "Sert fren", value: "\(ride.hardBrakes)")
                    StatTile(title: "Sert hızlanma", value: "\(ride.hardAccels)")
                }

                CardSection(title: "Hız dağılımı") {
                    BandBar(distances: ride.bandDistances).frame(height: 16)
                    BandTable(distances: ride.bandDistances)
                }

                Button {
                    showCard = true
                } label: {
                    Label("Paylaşım kartı oluştur", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(Fmt.day(ride.start))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCard) {
            ShareCardSheet(ride: ride, segments: segments)
        }
    }
}

struct RouteMap: View {
    let segments: [RouteSegment]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(SpeedBands.color(segment.band), lineWidth: 5)
            }
            if let first = segments.first?.coordinates.first {
                Marker("Başlangıç", systemImage: "flag", coordinate: first)
                    .tint(.green)
            }
            if let last = segments.last?.coordinates.last {
                Marker("Bitiş", systemImage: "flag.checkered", coordinate: last)
                    .tint(.red)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

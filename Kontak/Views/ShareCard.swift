import SwiftUI
import CoreLocation

/// 9:16 story card. Laid out at 360×640 points, rendered at 3× → 1080×1920 px.
struct ShareCardView: View {
    let ride: Ride
    let segments: [RouteSegment]

    var body: some View {
        let total = ride.distance
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A1D24), Color(hex: 0x0B0D11)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("KONTAK")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text(Fmt.dayTime(ride.start))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                RouteDrawing(segments: segments)
                    .frame(height: 230)
                    .padding(.vertical, 16)

                (Text(Fmt.kmValue(total))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                 + Text(" km")
                    .font(.system(size: 22, weight: .bold, design: .rounded)))
                    .monospacedDigit()

                HStack(spacing: 0) {
                    cardStat("SÜRE", Fmt.duration(ride.totalTime))
                    cardStat("ORT. HIZ", Fmt.speed(ride.avgSpeed))
                    cardStat("AZAMİ", Fmt.speed(ride.maxSpeed))
                }
                .padding(.top, 6)

                Text("HIZ DAĞILIMI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 22)

                BandBar(distances: ride.bandDistances)
                    .frame(height: 14)
                    .padding(.top, 8)

                VStack(spacing: 7) {
                    ForEach(0..<SpeedBands.count, id: \.self) { i in
                        let d = ride.bandDistance(i)
                        if d > 0 {
                            HStack(spacing: 8) {
                                Circle().fill(SpeedBands.color(i)).frame(width: 8, height: 8)
                                Text("\(SpeedBands.label(i)) km/h")
                                Spacer()
                                Text(Fmt.km(d))
                                Text(Fmt.percent(d, of: total))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 0)
            }
            .padding(24)
            .foregroundStyle(.white)
        }
        .frame(width: 360, height: 640)
    }

    private func cardStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The route drawn as colored lines, without a map underneath.
struct RouteDrawing: View {
    let segments: [RouteSegment]

    var body: some View {
        Canvas { ctx, size in
            let all = segments.flatMap(\.coordinates)
            guard all.count > 1 else { return }

            let lats = all.map(\.latitude), lons = all.map(\.longitude)
            let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
            let kx = cos((minLat + maxLat) / 2 * .pi / 180)
            let w = max((maxLon - minLon) * kx, 1e-9)
            let h = max(maxLat - minLat, 1e-9)
            let pad: CGFloat = 10
            let scale: CGFloat = min((size.width - 2 * pad) / CGFloat(w), (size.height - 2 * pad) / CGFloat(h))
            let ox: CGFloat = (size.width - CGFloat(w) * scale) / 2
            let oy: CGFloat = (size.height - CGFloat(h) * scale) / 2

            func point(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: ox + CGFloat((c.longitude - minLon) * kx) * scale,
                        y: oy + CGFloat(maxLat - c.latitude) * scale)
            }

            let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            for segment in segments {
                guard let first = segment.coordinates.first else { continue }
                var path = Path()
                path.move(to: point(first))
                for c in segment.coordinates.dropFirst() {
                    path.addLine(to: point(c))
                }
                ctx.stroke(path, with: .color(SpeedBands.color(segment.band)), style: style)
            }

            let start = point(all[0]), end = point(all[all.count - 1])
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 2.5)
        }
    }
}

struct ShareCardSheet: View {
    let ride: Ride
    let segments: [RouteSegment]
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("Kontak sürüşü", image: Image(uiImage: image))) {
                        Label("Paylaş veya kaydet", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical)
            .navigationTitle("Paylaşım kartı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear { render() }
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: ShareCardView(ride: ride, segments: segments))
        renderer.scale = 3
        image = renderer.uiImage
    }
}

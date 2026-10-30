import SwiftUI

/// Horizontal bar split by how much distance was ridden in each speed band.
struct BandBar: View {
    let distances: [Double]

    var body: some View {
        GeometryReader { geo in
            let total = distances.reduce(0, +)
            let used = distances.indices.filter { distances[$0] > 0 }
            let gap: CGFloat = 2
            let available = max(geo.size.width - gap * CGFloat(max(used.count - 1, 0)), 0)
            HStack(spacing: gap) {
                if total <= 0 {
                    Rectangle().fill(Color.white.opacity(0.1))
                } else {
                    ForEach(used, id: \.self) { i in
                        Rectangle()
                            .fill(SpeedBands.color(i))
                            .frame(width: max(available * CGFloat(distances[i] / total), 2))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipShape(Capsule())
        }
    }
}

/// Rows of "band · km · %".
struct BandTable: View {
    let distances: [Double]
    var hideEmpty = false

    var body: some View {
        let total = distances.reduce(0, +)
        VStack(spacing: 8) {
            ForEach(0..<SpeedBands.count, id: \.self) { i in
                let d = i < distances.count ? distances[i] : 0
                if !(hideEmpty && d <= 0) {
                    HStack {
                        Circle().fill(SpeedBands.color(i)).frame(width: 10, height: 10)
                        Text("\(SpeedBands.label(i)) km/h")
                        Spacer()
                        Text(Fmt.km(d)).monospacedDigit()
                        Text(Fmt.percent(d, of: total))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

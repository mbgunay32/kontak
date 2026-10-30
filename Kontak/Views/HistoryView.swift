import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Ride.start, order: .reverse) private var rides: [Ride]
    @Environment(\.modelContext) private var context
    @State private var period: Period = .week

    enum Period: String, CaseIterable, Identifiable {
        case week = "Bu hafta"
        case month = "Bu ay"
        case all = "Tümü"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }

                Section("Sürüşler") {
                    if rides.isEmpty {
                        Text("Henüz kayıtlı sürüş yok.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rides) { ride in
                        NavigationLink(value: ride) {
                            RideRow(ride: ride)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Geçmiş")
            .navigationDestination(for: Ride.self) { ride in
                RideDetailView(ride: ride)
            }
        }
    }

    private var summary: some View {
        let selected = ridesIn(period)
        let total = selected.reduce(0) { $0 + $1.distance }
        let time = selected.reduce(0) { $0 + $1.movingTime }
        let bands = (0..<SpeedBands.count).map { i in selected.reduce(0) { $0 + $1.bandDistance(i) } }

        return VStack(alignment: .leading, spacing: 14) {
            Picker("Dönem", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.kmValue(total))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("km").font(.title3.bold()).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(selected.count) sürüş")
                    Text(Fmt.duration(time))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            BandBar(distances: bands).frame(height: 14)
            BandTable(distances: bands)
        }
        .padding(.vertical, 6)
    }

    private func ridesIn(_ period: Period) -> [Ride] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let component: Calendar.Component
        switch period {
        case .all: return rides
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        guard let interval = calendar.dateInterval(of: component, for: Date()) else { return rides }
        return rides.filter { interval.contains($0.start) }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(rides[index])
        }
        try? context.save()
    }
}

struct RideRow: View {
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.dayTime(ride.start)).font(.subheadline)
                Spacer()
                Text(Fmt.km(ride.distance)).font(.headline).monospacedDigit()
            }
            HStack {
                BandBar(distances: ride.bandDistances).frame(height: 6)
                Text(Fmt.duration(ride.totalTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

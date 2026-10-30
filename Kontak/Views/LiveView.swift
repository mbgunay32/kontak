import SwiftUI

struct LiveView: View {
    @Environment(RideRecorder.self) private var recorder

    private var isRecording: Bool { recorder.state == .recording }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    speedometer
                    statsRow
                    CardSection(title: "Hız dağılımı") {
                        BandBar(distances: recorder.stats.bandDistances).frame(height: 16)
                        BandTable(distances: recorder.stats.bandDistances)
                    }
                    startStopButton
                    status
                }
                .padding()
            }
            .navigationTitle("Kontak")
        }
    }

    private var speedometer: some View {
        VStack(spacing: 0) {
            Text("\(Int((recorder.currentSpeed * 3.6).rounded()))")
                .font(.system(size: 110, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRecording ? SpeedBands.color(SpeedBands.index(forSpeed: recorder.currentSpeed)) : Color.secondary)
                .contentTransition(.numericText())
            Text("km/h")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var statsRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                StatTile(title: "Mesafe", value: Fmt.km(recorder.stats.distance))
                StatTile(title: "Süre", value: Fmt.duration(elapsed(at: context.date)))
                StatTile(title: "Azami", value: Fmt.speed(recorder.stats.maxSpeed))
            }
        }
    }

    private func elapsed(at date: Date) -> Double {
        guard let start = recorder.startDate else { return 0 }
        return date.timeIntervalSince(start)
    }

    private var startStopButton: some View {
        Button {
            if isRecording {
                recorder.stop()
            } else {
                recorder.start()
            }
        } label: {
            Label(isRecording ? "Sürüşü bitir" : "Sürüşü başlat",
                  systemImage: isRecording ? "stop.fill" : "play.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? .red : Theme.accent)
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 10) {
            if !recorder.canRecord {
                Button("Konum iznini ver") { recorder.requestPermission() }
                    .buttonStyle(.bordered)
            } else if recorder.autoMode && !recorder.hasAlways {
                VStack(spacing: 6) {
                    Text("Otomatik kayıt için konum izni \"Her Zaman\" olmalı.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("İzni ayarla") { recorder.requestPermission() }
                        .buttonStyle(.bordered)
                }
            } else if isRecording && recorder.isAutoStarted {
                Text("Otomatik başladı · 5 dakika durunca kendiliğinden biter")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !isRecording && recorder.autoMode {
                Text("Otomatik kayıt açık · 20 km/h'yi geçince başlar")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let message = recorder.lastMessage, !isRecording {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

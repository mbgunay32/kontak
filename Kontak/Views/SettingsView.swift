import SwiftUI

struct SettingsView: View {
    @Environment(RideRecorder.self) private var recorder
    @State private var shared: SharedFile?
    @State private var lineCount = 0
    @State private var confirmClear = false

    var body: some View {
        @Bindable var recorder = recorder
        NavigationStack {
            Form {
                Section {
                    Toggle("Otomatik kayıt", isOn: $recorder.autoMode)
                } footer: {
                    Text("Açıkken hızın 20 km/h'yi geçince kayıt kendiliğinden başlar, 5 dakika durunca biter. Bunun için konum izni \"Her Zaman\" olmalı. Uygulamayı arka plandan yukarı kaydırıp kapatma.")
                }

                Section("Konum izni") {
                    LabeledContent("Durum", value: recorder.permissionText)
                    if !recorder.hasAlways {
                        Button("İzni ayarla") { recorder.requestPermission() }
                    }
                }

                Section("Hız aralıkları") {
                    ForEach(0..<SpeedBands.count, id: \.self) { i in
                        HStack {
                            Circle().fill(SpeedBands.color(i)).frame(width: 12, height: 12)
                            Text("\(SpeedBands.label(i)) km/h")
                        }
                    }
                }

                Section {
                    Button {
                        if let url = DiagLog.shared.exportForSharing() {
                            shared = SharedFile(url: url)
                        }
                    } label: {
                        Label("Günlüğü paylaş", systemImage: "doc.text")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Günlüğü temizle", systemImage: "trash")
                    }
                } header: {
                    Text("Tanılama")
                } footer: {
                    Text("Günlük, uygulamanın ne zaman kayda başladığını, GPS'in ne kadar doğru olduğunu ve neyi neden saydığını yazar. \(lineCount) satır.")
                }

                Section {
                    LabeledContent("Sürüm", value: appVersion)
                } footer: {
                    Text("Kontak kişisel kullanım için yazıldı. Sürüşlerin yalnızca bu telefonda saklanır, hiçbir yere gönderilmez.")
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear { lineCount = DiagLog.shared.lineCount }
            .sheet(item: $shared) { file in
                ActivityView(url: file.url)
            }
            .confirmationDialog("Günlük silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Günlüğü temizle", role: .destructive) {
                    DiagLog.shared.clear()
                    lineCount = DiagLog.shared.lineCount
                }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

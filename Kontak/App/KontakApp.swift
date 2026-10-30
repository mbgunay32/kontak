import SwiftUI
import SwiftData

@main
struct KontakApp: App {
    private let container: ModelContainer
    @State private var recorder: RideRecorder

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Ride.self)
        } catch {
            fatalError("Veritabanı açılamadı: \(error)")
        }
        self.container = container

        let recorder = RideRecorder()
        recorder.attach(context: container.mainContext)
        _recorder = State(initialValue: recorder)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(recorder)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            LiveView()
                .tabItem { Label("Sürüş", systemImage: "gauge.with.needle") }
            HistoryView()
                .tabItem { Label("Geçmiş", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
    }
}

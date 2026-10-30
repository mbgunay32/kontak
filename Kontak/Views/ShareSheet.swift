import SwiftUI
import UIKit

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// System share sheet for a file (AirDrop, Files, WhatsApp, Mail…).
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

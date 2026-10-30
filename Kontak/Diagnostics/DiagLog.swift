import Foundation
import UIKit

/// Plain-text diagnostic log kept on the phone, shared from Settings.
final class DiagLog {
    static let shared = DiagLog()

    let url: URL
    private let queue = DispatchQueue(label: "kontak.diaglog")
    private let maxBytes = 2_000_000
    private let keepBytes = 1_200_000

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("kontak-gunluk.txt")
    }

    func log(_ tag: String, _ message: String) {
        let date = Date()
        queue.async {
            let line = "\(self.timeFormatter.string(from: date)) [\(tag)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: self.url)
            }
            self.trimIfNeeded()
        }
    }

    private func trimIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        var tail = data.suffix(keepBytes)
        if let newline = tail.firstIndex(of: 0x0A) {
            tail = tail[tail.index(after: newline)...]
        }
        try? Data(tail).write(to: url, options: .atomic)
    }

    var lineCount: Int {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
            return text.split(separator: "\n").count
        }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: url)
        }
        log("günlük", "temizlendi")
    }

    /// Copies the log to a dated file with a short device header, ready for the share sheet.
    func exportForSharing() -> URL? {
        let header = """
        Kontak tanılama günlüğü
        Uygulama: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
        iOS: \(UIDevice.current.systemVersion) · Cihaz: \(Self.deviceModel)
        Dışa aktarma: \(timeFormatter.string(from: Date()))
        ----------------------------------------

        """
        return queue.sync {
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? "(günlük boş)"
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyyMMdd-HHmm"
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("Kontak-gunluk-\(stamp.string(from: Date())).txt")
            do {
                try (header + body).write(to: out, atomically: true, encoding: .utf8)
                return out
            } catch {
                return nil
            }
        }
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

/// Writes a ride's raw points as CSV so it can be analysed on a computer.
enum RideExport {
    static func csv(for ride: Ride) -> URL? {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "# Kontak sürüş verisi",
            "# başlangıç: \(iso.string(from: ride.start)) · bitiş: \(iso.string(from: ride.end))",
            "# mesafe_m: \(Int(ride.distance)) · hareket_s: \(Int(ride.movingTime)) · durma_s: \(Int(ride.stoppedTime))",
            "# azami_kmh: \(Int(ride.maxSpeed * 3.6)) · sert_fren: \(ride.hardBrakes) · sert_hizlanma: \(ride.hardAccels) · durak: \(ride.stopCount)",
            "# hiz_araliklari_m: " + (0..<SpeedBands.count).map { "\(SpeedBands.label($0))=\(Int(ride.bandDistance($0)))" }.joined(separator: " "),
            "time,lat,lon,speed_kmh,alt_m",
        ]
        for p in ride.points {
            let alt = p.alt.map { String(format: "%.1f", $0) } ?? ""
            lines.append(String(format: "%@,%.6f,%.6f,%.1f,%@",
                                iso.string(from: Date(timeIntervalSince1970: p.t)),
                                p.lat, p.lon, p.speed * 3.6, alt))
        }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kontak-surus-\(stamp.string(from: ride.start)).csv")
        do {
            try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            return out
        } catch {
            return nil
        }
    }
}

import Foundation

public final class LocalMetaStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(filename: String = "meta_progress.json") {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    public func saveMeta(_ meta: MetaProgress) {
        do {
            let data = try encoder.encode(meta)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            LocalEventLogger.shared.log("save_meta_failed", payload: ["error": "\(error)"])
        }
    }

    public func loadMeta() -> MetaProgress? {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(MetaProgress.self, from: data)
        } catch {
            LocalEventLogger.shared.log("load_meta_failed", payload: ["error": "\(error)"])
            return nil
        }
    }

    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

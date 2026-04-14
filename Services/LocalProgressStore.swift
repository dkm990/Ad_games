import Foundation

public final class LocalProgressStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(filename: String = "session_state.json") {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    public func saveState(_ state: GameSessionState) {
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            LocalEventLogger.shared.log("save_state_failed", payload: ["error": "\(error)"])
        }
    }

    public func loadState() -> GameSessionState? {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(GameSessionState.self, from: data)
        } catch {
            LocalEventLogger.shared.log("load_state_failed", payload: ["error": "\(error)"])
            return nil
        }
    }

    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

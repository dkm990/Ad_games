import Foundation

public final class LocalEventLogger {
    public static let shared = LocalEventLogger()

    private init() {}

    public func log(_ name: String, payload: [String: String] = [:]) {
        let sorted = payload
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
        print("[event] \(name) \(sorted)")
    }
}

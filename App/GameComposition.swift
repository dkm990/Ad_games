import Foundation

public enum GameComposition {
    public static func makeStore(configURL: URL) throws -> GameSessionStore {
        let config = try EconomyConfigLoader.load(from: configURL)
        let progressStore = LocalProgressStore()
        return GameSessionStore(config: config, progressStore: progressStore)
    }
}

import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    private var skView: SKView {
        view as! SKView
    }

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let configURL = try resolveConfigURL()
            let store = try GameComposition.makeStore(configURL: configURL)
            let orchestrator = GameSceneOrchestrator(stateSource: store)
            let config = try EconomyConfigLoader.load(from: configURL)

            let scene = GamePlayScene(size: view.bounds.size, orchestrator: orchestrator, config: config)
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
            skView.ignoresSiblingOrder = true
            skView.preferredFramesPerSecond = 60
        } catch {
            let label = UILabel(frame: view.bounds)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = .white
            label.backgroundColor = .black
            label.text = "Failed to boot game scene:\n\(error)"
            view.addSubview(label)
        }
    }

    private func resolveConfigURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "economy.v0_1", withExtension: "json") {
            return url
        }

        if let url = Bundle.main.url(forResource: "economy.v0_1", withExtension: "json", subdirectory: "Config") {
            return url
        }

        throw NSError(domain: "GameConfig", code: 404, userInfo: [NSLocalizedDescriptionKey: "economy.v0_1.json not found in bundle"]) 
    }
}

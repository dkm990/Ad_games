import SpriteKit
import UIKit

final class GamePlayScene: SKScene {
    private let orchestrator: GameSceneOrchestrator
    private let config: EconomyConfig

    private let worldNode = SKNode()
    private let player = SKShapeNode(circleOfRadius: 18)
    private let cameraNode = SKCameraNode()
    private let hudNode = SKNode()

    private let carryLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let guidanceLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")

    private var resourceNodes: [Int: SKShapeNode] = [:]
    private var resourceRespawnTime: [Int: TimeInterval] = [:]
    private var interactionZoneNodes: [Int: SKShapeNode] = [:]
    private var highlightNodes: [Int: SKShapeNode] = [:]

    private var touchLocation: CGPoint?
    private var velocity: CGVector = .zero
    private var lastUpdateTime: TimeInterval = 0
    private var lastPickupCheckTime: TimeInterval = 0

    init(size: CGSize, orchestrator: GameSceneOrchestrator, config: EconomyConfig) {
        self.orchestrator = orchestrator
        self.config = config
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        addChild(worldNode)
        buildMap()
        buildPlayer()
        buildResources()
        setupCameraAndHUD()
        refreshHUD()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = touches.first.map { $0.location(in: worldNode) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = touches.first.map { $0.location(in: worldNode) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = nil
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(max(currentTime - lastUpdateTime, 0), 1.0 / 20.0)
        lastUpdateTime = currentTime

        updateMovement(dt: dt)
        updateCamera(dt: dt)
        updateResourceRespawns(currentTime: currentTime)
        runPickupIfNeeded(currentTime: currentTime)
        updateHighlighting()
        refreshHUD()
    }

    private func buildMap() {
        let floor = SKShapeNode(rectOf: CGSize(width: 1200, height: 1200), cornerRadius: 6)
        floor.fillColor = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
        floor.strokeColor = UIColor(red: 0.21, green: 0.25, blue: 0.29, alpha: 1)
        floor.lineWidth = 6
        floor.zPosition = 0
        worldNode.addChild(floor)

        createBlockingRect(size: CGSize(width: 180, height: 44), position: CGPoint(x: -120, y: 40))
        createBlockingRect(size: CGSize(width: 200, height: 44), position: CGPoint(x: 200, y: -100))
        createBlockingRect(size: CGSize(width: 140, height: 44), position: CGPoint(x: -220, y: -220))
        createBoundary(size: CGSize(width: 1120, height: 1120))
    }

    private func createBoundary(size: CGSize) {
        let boundary = SKNode()
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        ))
        boundary.physicsBody?.isDynamic = false
        boundary.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
        boundary.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        boundary.physicsBody?.contactTestBitMask = 0
        worldNode.addChild(boundary)
    }

    private func createBlockingRect(size: CGSize, position: CGPoint) {
        let node = SKShapeNode(rectOf: size, cornerRadius: 8)
        node.position = position
        node.fillColor = UIColor(red: 0.18, green: 0.27, blue: 0.35, alpha: 1)
        node.strokeColor = UIColor(red: 0.44, green: 0.66, blue: 0.83, alpha: 1)
        node.lineWidth = 3
        node.zPosition = 1

        node.physicsBody = SKPhysicsBody(rectangleOf: size)
        node.physicsBody?.isDynamic = false
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
        node.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        node.physicsBody?.contactTestBitMask = 0

        worldNode.addChild(node)
    }

    private func buildPlayer() {
        player.fillColor = UIColor(red: 0.25, green: 0.94, blue: 0.45, alpha: 1)
        player.strokeColor = UIColor(red: 0.04, green: 0.2, blue: 0.08, alpha: 1)
        player.lineWidth = 3
        player.zPosition = 10
        player.position = CGPoint(x: 0, y: 0)

        let body = SKPhysicsBody(circleOfRadius: 18)
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 8
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = CollisionLayer.player.rawValue
        body.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        body.contactTestBitMask = CollisionPolicy.playerContactMask.rawValue
        player.physicsBody = body

        worldNode.addChild(player)
    }

    private func buildResources() {
        let positions = [
            CGPoint(x: -320, y: 220),
            CGPoint(x: -120, y: 280),
            CGPoint(x: 80, y: 220),
            CGPoint(x: 260, y: 180),
            CGPoint(x: 320, y: -20)
        ]

        for (index, point) in positions.enumerated() {
            let id = 100 + index
            let node = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 4)
            node.position = point
            node.fillColor = UIColor(red: 1.0, green: 0.75, blue: 0.22, alpha: 1)
            node.strokeColor = UIColor(red: 0.62, green: 0.33, blue: 0.02, alpha: 1)
            node.lineWidth = 2
            node.zPosition = 5
            node.name = "resource_\(id)"

            let body = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: 28))
            body.isDynamic = false
            body.affectedByGravity = false
            body.categoryBitMask = CollisionLayer.resourceNode.rawValue
            body.collisionBitMask = CollisionPolicy.resourceCollisionMask.rawValue
            body.contactTestBitMask = CollisionLayer.player.rawValue
            node.physicsBody = body

            let highlight = SKShapeNode(rectOf: CGSize(width: 40, height: 40), cornerRadius: 8)
            highlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
            highlight.glowWidth = 3
            highlight.lineWidth = 2
            highlight.fillColor = .clear
            highlight.isHidden = true
            highlight.zPosition = 7
            node.addChild(highlight)

            let interactionZone = SKShapeNode(circleOfRadius: config.player.pickupRadius)
            interactionZone.position = point
            interactionZone.strokeColor = .clear
            interactionZone.fillColor = .clear
            interactionZone.zPosition = 2
            interactionZone.name = "interaction_resource_\(id)"

            let interactionBody = SKPhysicsBody(circleOfRadius: config.player.pickupRadius)
            interactionBody.isDynamic = false
            interactionBody.affectedByGravity = false
            interactionBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
            interactionBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
            interactionBody.contactTestBitMask = CollisionLayer.player.rawValue
            interactionZone.physicsBody = interactionBody

            worldNode.addChild(interactionZone)
            worldNode.addChild(node)

            resourceNodes[id] = node
            interactionZoneNodes[id] = interactionZone
            highlightNodes[id] = highlight
        }
    }

    private func setupCameraAndHUD() {
        camera = cameraNode
        addChild(cameraNode)

        carryLabel.fontSize = 18
        carryLabel.horizontalAlignmentMode = .left
        carryLabel.verticalAlignmentMode = .center
        carryLabel.fontColor = .white
        carryLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.42)

        guidanceLabel.fontSize = 16
        guidanceLabel.horizontalAlignmentMode = .left
        guidanceLabel.verticalAlignmentMode = .center
        guidanceLabel.fontColor = UIColor(red: 0.78, green: 0.9, blue: 1.0, alpha: 1)
        guidanceLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.36)

        hudNode.zPosition = 1000
        hudNode.addChild(carryLabel)
        hudNode.addChild(guidanceLabel)
        cameraNode.addChild(hudNode)
    }

    private func updateMovement(dt: TimeInterval) {
        let acceleration = CGFloat(config.player.playerAcceleration)
        let effectiveMaxSpeed = CGFloat(orchestrator.effectiveMaxSpeed)

        var inputVector = CGVector.zero
        if let location = touchLocation {
            let delta = CGVector(dx: location.x - player.position.x, dy: location.y - player.position.y)
            let length = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
            if length > 8 {
                inputVector = CGVector(dx: delta.dx / length, dy: delta.dy / length)
            }
        }

        if inputVector == .zero {
            velocity.dx *= 0.84
            velocity.dy *= 0.84
            if abs(velocity.dx) < 1 { velocity.dx = 0 }
            if abs(velocity.dy) < 1 { velocity.dy = 0 }
        } else {
            velocity.dx += inputVector.dx * acceleration * CGFloat(dt)
            velocity.dy += inputVector.dy * acceleration * CGFloat(dt)
            let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
            let maxAllowed = max(120, effectiveMaxSpeed)
            if speed > maxAllowed {
                let k = maxAllowed / speed
                velocity.dx *= k
                velocity.dy *= k
            }
        }

        player.physicsBody?.velocity = velocity
    }

    private func updateCamera(dt: TimeInterval) {
        let followStrength: CGFloat = min(1, CGFloat(dt) * 8)
        cameraNode.position.x += (player.position.x - cameraNode.position.x) * followStrength
        cameraNode.position.y += (player.position.y - cameraNode.position.y) * followStrength
    }

    private func runPickupIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastPickupCheckTime > 0.1 else { return }
        lastPickupCheckTime = currentTime

        let state = orchestrator.sessionState
        let carryCapacity = max(1, orchestrator.effectiveCarryCapacity)
        guard state.carryAmount < carryCapacity else { return }

        let pickupRadius = CGFloat(config.player.pickupRadius)
        let nearest = resourceNodes
            .filter { _, node in
                node.isHidden == false && node.parent != nil
            }
            .min { lhs, rhs in
                player.position.distanceSquared(to: lhs.value.position) < player.position.distanceSquared(to: rhs.value.position)
            }

        guard let (id, node) = nearest else { return }
        let distance = player.position.distance(to: node.position)
        guard distance <= pickupRadius else { return }

        _ = id
        orchestrator.perform(.collectRaw(units: 1))
        node.isHidden = true
        interactionZoneNodes[id]?.isHidden = true
        resourceRespawnTime[id] = currentTime + 2.0
    }

    private func updateResourceRespawns(currentTime: TimeInterval) {
        for (id, respawnTime) in resourceRespawnTime where currentTime >= respawnTime {
            resourceNodes[id]?.isHidden = false
            interactionZoneNodes[id]?.isHidden = false
            resourceRespawnTime.removeValue(forKey: id)
        }
    }

    private func updateHighlighting() {
        let guidance = orchestrator.sessionState.guidanceState
        let candidates: [InteractionCandidate] = resourceNodes.compactMap { id, node in
            guard node.isHidden == false else { return nil }
            let distance = player.position.distance(to: node.position)
            let inRange = distance <= CGFloat(config.player.pickupRadius)
            return InteractionCandidate(
                zoneID: id,
                kind: .resource,
                distanceToPlayer: distance,
                isWithinInteractionRadius: inRange
            )
        }

        let decision = PrimaryTargetResolver.resolve(candidates: candidates, guidance: guidance)
        for (id, highlight) in highlightNodes {
            let active = decision.primaryZoneID == id
            if active {
                if highlight.isHidden {
                    highlight.isHidden = false
                    let pulse = SKAction.sequence([
                        SKAction.scale(to: 1.12, duration: 0.25),
                        SKAction.scale(to: 1.0, duration: 0.25)
                    ])
                    highlight.run(SKAction.repeatForever(pulse), withKey: "pulse")
                }
            } else {
                highlight.removeAction(forKey: "pulse")
                highlight.isHidden = true
                highlight.setScale(1.0)
            }
        }
    }

    private func refreshHUD() {
        let state = orchestrator.sessionState
        let capacity = max(1, orchestrator.effectiveCarryCapacity)
        carryLabel.text = "Carry: \(state.carryAmount)/\(capacity)"
        guidanceLabel.text = GuidanceTextPresenter.text(for: state.guidanceState)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt(distanceSquared(to: other))
    }

    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

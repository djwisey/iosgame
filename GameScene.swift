import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum Mode {
        case endless
        case daily
    }

    private struct PhysicsCategory {
        static let none: UInt32 = 0
        static let player: UInt32 = 1 << 0
        static let obstacle: UInt32 = 1 << 1
        static let world: UInt32 = 1 << 2
    }

    private let stateMachine = GameStateMachine()
    private let pool = ObstaclePool()
    private let scoreManager = ScoreManager.shared

    private var playerNode = SKShapeNode(circleOfRadius: 18)
    private var playerTrail: SKEmitterNode?
    private var targetX: CGFloat = 0
    private var isTouching = false

    private var lastUpdateTime: TimeInterval = 0
    private var timeAlive: TimeInterval = 0
    private var spawnTimer: TimeInterval = 0
    private var scoreAccumulator: Double = 0

    private var baseSpeed: CGFloat = 220
    private var spawnInterval: TimeInterval = 1.4

    private var titleOverlay = SKNode()
    private var hudOverlay = SKNode()
    private var gameOverOverlay = SKNode()

    private var scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var bestLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var titlePlayLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var titleModeLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var titleSeedLabel = SKLabelNode(fontNamed: "AvenirNext-Regular")
    private var gameOverTitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var gameOverScore = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var gameOverBest = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var gameOverRestart = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private var mode: Mode = .endless
    private var dailySeed: UInt64 = 0
    private var dailyRNG = SplitMix64(seed: 0)

    private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    private var showPhysicsBodies: Bool = false
    private var slowMotion: Bool = false

    private var freezeRemaining: TimeInterval = 0
    private var pendingGameOver = false
    private var cameraNode = SKCameraNode()

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        view.showsPhysics = showPhysicsBodies

        setupCamera()
        setupBackground()
        setupPlayer()
        setupUI()
        setupStateMachine()
        AdManager.shared.preloadInterstitial()
    }

    private func setupCamera() {
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        camera = cameraNode
        addChild(cameraNode)
    }

    private func setupBackground() {
        let stars = SKEmitterNode()
        stars.particleBirthRate = 4
        stars.particleLifetime = 12
        stars.particleSpeed = -40
        stars.particleSpeedRange = 20
        stars.particleAlpha = 0.8
        stars.particleAlphaRange = 0.2
        stars.particleScale = 0.2
        stars.particleScaleRange = 0.1
        stars.particleColor = .white
        stars.position = CGPoint(x: size.width / 2, y: size.height)
        stars.particlePositionRange = CGVector(dx: size.width, dy: 0)
        stars.particleColorBlendFactor = 1
        stars.zPosition = -10
        addChild(stars)
    }

    private func setupPlayer() {
        playerNode.fillColor = .white
        playerNode.strokeColor = .clear
        playerNode.alpha = 0
        playerNode.position = CGPoint(x: size.width / 2, y: size.height * 0.2)
        addChild(playerNode)
        targetX = playerNode.position.x
    }

    private func setupUI() {
        setupTitleOverlay()
        setupHUDOverlay()
        setupGameOverOverlay()
        showTitle()
    }

    private func setupTitleOverlay() {
        titleOverlay.zPosition = 50
        titleOverlay.position = CGPoint(x: 0, y: 0)

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "TOUCH RUNNER"
        title.fontSize = 40
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
        titleOverlay.addChild(title)

        titlePlayLabel.text = "PLAY"
        titlePlayLabel.name = "play"
        titlePlayLabel.fontSize = 30
        titlePlayLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        titleOverlay.addChild(titlePlayLabel)

        titleModeLabel.text = "MODE: ENDLESS"
        titleModeLabel.name = "mode"
        titleModeLabel.fontSize = 20
        titleModeLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        titleOverlay.addChild(titleModeLabel)

        titleSeedLabel.text = ""
        titleSeedLabel.fontSize = 14
        titleSeedLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
        titleOverlay.addChild(titleSeedLabel)

        addChild(titleOverlay)
    }

    private func setupHUDOverlay() {
        hudOverlay.zPosition = 40
        scoreLabel.fontSize = 22
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 20, y: size.height - 40)
        hudOverlay.addChild(scoreLabel)

        bestLabel.fontSize = 16
        bestLabel.horizontalAlignmentMode = .left
        bestLabel.position = CGPoint(x: 20, y: size.height - 70)
        hudOverlay.addChild(bestLabel)

        addChild(hudOverlay)
    }

    private func setupGameOverOverlay() {
        gameOverOverlay.zPosition = 60
        gameOverTitle.text = "GAME OVER"
        gameOverTitle.fontSize = 36
        gameOverTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.65)
        gameOverOverlay.addChild(gameOverTitle)

        gameOverScore.fontSize = 22
        gameOverScore.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        gameOverOverlay.addChild(gameOverScore)

        gameOverBest.fontSize = 18
        gameOverBest.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
        gameOverOverlay.addChild(gameOverBest)

        gameOverRestart.text = "RESTART"
        gameOverRestart.name = "restart"
        gameOverRestart.fontSize = 26
        gameOverRestart.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
        gameOverOverlay.addChild(gameOverRestart)

        gameOverOverlay.isHidden = true
        addChild(gameOverOverlay)
    }

    private func setupStateMachine() {
        stateMachine.onChange = { [weak self] newPhase in
            guard let self else { return }
            switch newPhase {
            case .title:
                self.showTitle()
            case .playing:
                self.startGame()
            case .gameOver:
                self.showGameOver()
            }
        }
    }

    private func showTitle() {
        titleOverlay.isHidden = false
        hudOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        updateModeLabel()
    }

    private func startGame() {
        titleOverlay.isHidden = true
        hudOverlay.isHidden = false
        gameOverOverlay.isHidden = true
        resetGame()
    }

    private func showGameOver() {
        hudOverlay.isHidden = true
        gameOverOverlay.isHidden = false
        gameOverScore.text = "Score: \(scoreManager.score)"
        gameOverBest.text = "Best: \(scoreManager.bestScore)"
        scoreManager.finalizeRun()
        if scoreManager.runCount % 2 == 0 {
            AdManager.shared.showInterstitialIfReady(reason: "game_over")
        }
    }

    private func resetGame() {
        scoreManager.resetScore()
        timeAlive = 0
        spawnTimer = 0
        scoreAccumulator = 0
        baseSpeed = 220
        spawnInterval = 1.4
        pool.reset()
        removeAllObstacles()
        deactivatePlayer()
        updateHUD()
    }

    private func removeAllObstacles() {
        let activeNodes = pool.active
        for node in activeNodes {
            pool.enqueue(node)
        }
    }

    private func updateHUD() {
        scoreLabel.text = "Score: \(scoreManager.score)"
        bestLabel.text = "Best: \(scoreManager.bestScore)"
    }

    private func updateModeLabel() {
        switch mode {
        case .endless:
            titleModeLabel.text = "MODE: ENDLESS"
            titleSeedLabel.text = ""
        case .daily:
            let seedString = dailySeedString()
            titleModeLabel.text = "MODE: DAILY"
            titleSeedLabel.text = "Daily Seed: \(seedString)"
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        switch stateMachine.phase {
        case .title:
            handleTitleTouch(location)
        case .gameOver:
            handleGameOverTouch(location)
        case .playing:
            isTouching = true
            targetX = clampX(location.x)
            if playerNode.alpha == 0 {
                activatePlayer()
                if isPlayerOverlappingObstacle() {
                    triggerDeath()
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if stateMachine.phase == .playing {
            targetX = clampX(location.x)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if stateMachine.phase == .playing {
            isTouching = false
            deactivatePlayer()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        var delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if slowMotion {
            delta *= 0.2
        }

        if freezeRemaining > 0 {
            freezeRemaining -= delta
            return
        }

        if pendingGameOver {
            pendingGameOver = false
            stateMachine.transition(to: .gameOver)
            return
        }

        guard stateMachine.phase == .playing else { return }

        timeAlive += delta
        spawnTimer += delta
        baseSpeed = 220 + min(CGFloat(timeAlive) * 12, 280)
        spawnInterval = max(0.6, 1.4 - timeAlive * 0.02)

        scoreAccumulator += delta * 100
        let newPoints = Int(scoreAccumulator)
        if newPoints > 0 {
            scoreAccumulator -= Double(newPoints)
            scoreManager.add(points: newPoints)
        }

        if spawnTimer >= spawnInterval {
            spawnTimer = 0
            spawnObstacle()
        }

        moveObstacles(delta: delta)
        updatePlayer(delta: delta)
        detectNearMisses()
        updateHUD()
    }

    private func updatePlayer(delta: TimeInterval) {
        guard isTouching, playerNode.alpha > 0 else { return }
        let smooth = min(1.0, CGFloat(delta) * 10)
        let newX = playerNode.position.x + (targetX - playerNode.position.x) * smooth
        playerNode.position = CGPoint(x: newX, y: size.height * 0.2)
        playerTrail?.position = .zero
    }

    private func activatePlayer() {
        playerNode.alpha = 1
        playerNode.setScale(0.7)
        playerNode.run(SKAction.scale(to: 1.0, duration: 0.08))
        playerNode.physicsBody = makePlayerBody()
        attachTrail()
        Haptics.light()
    }

    private func deactivatePlayer() {
        playerNode.physicsBody = nil
        playerNode.run(SKAction.fadeOut(withDuration: 0.05))
        playerTrail?.removeFromParent()
        playerTrail = nil
    }

    private func makePlayerBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(circleOfRadius: 18)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.player
        body.contactTestBitMask = PhysicsCategory.obstacle
        body.collisionBitMask = PhysicsCategory.none
        return body
    }

    private func attachTrail() {
        let style = scoreManager.currentTrailStyle()
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = style.birthRate
        emitter.particleLifetime = 0.4
        emitter.particleSpeed = style.speed
        emitter.particleSpeedRange = 10
        emitter.particleAlpha = 0.7
        emitter.particleAlphaRange = 0.3
        emitter.particleScale = style.particleSize / 50
        emitter.particleScaleRange = 0.05
        emitter.particleColor = style.color
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: 8, dy: 8)
        emitter.targetNode = self
        emitter.zPosition = -1
        playerNode.addChild(emitter)
        playerTrail = emitter
    }

    private func spawnObstacle() {
        let kind = randomObstacleKind()
        let obstacle = pool.dequeue(kind: kind)
        let obstacleSize = CGSize(width: 60, height: 24)
        let laneX = randomLaneX()
        let gapCenter = randomGapCenter()
        let gapWidth = CGFloat(max(120, 200 - timeAlive * 4))
        obstacle.speed = baseSpeed
        obstacle.userData = ["phase": randomDouble(in: 0...Double.pi * 2)]
        obstacle.configure(size: size, sceneWidth: size.width, laneX: laneX, gapCenter: gapCenter, gapWidth: gapWidth, obstacleSize: obstacleSize, categoryMask: PhysicsCategory.obstacle)
        pool.activate(obstacle)
        addChild(obstacle)
    }

    private func moveObstacles(delta: TimeInterval) {
        let deltaY = CGFloat(delta) * baseSpeed
        for obstacle in pool.active {
            obstacle.position.y -= deltaY
            if obstacle.kind == .mover {
                let phase = obstacle.userData?["phase"] as? Double ?? 0
                let oscillation = sin(timeAlive * Double(obstacle.oscillationSpeed) + phase)
                obstacle.position.x = obstacle.baseX + CGFloat(oscillation) * obstacle.oscillationAmplitude
            }
        }

        let activeNodes = pool.active
        for obstacle in activeNodes where obstacle.position.y < -120 {
            pool.enqueue(obstacle)
        }
    }

    private func detectNearMisses() {
        guard playerNode.alpha > 0 else { return }
        for obstacle in pool.active where !obstacle.nearMissed {
            for piece in obstacle.pieces {
                let worldPos = piece.convert(.zero, to: self)
                let distance = hypot(worldPos.x - playerNode.position.x, worldPos.y - playerNode.position.y)
                if distance < 50 {
                    obstacle.nearMissed = true
                    Haptics.light()
                    scoreManager.add(points: 10)
                    break
                }
            }
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if masks & PhysicsCategory.player != 0 && masks & PhysicsCategory.obstacle != 0 {
            triggerDeath()
        }
    }

    private func triggerDeath() {
        guard stateMachine.phase == .playing else { return }
        pendingGameOver = true
        freezeRemaining = 0.15
        Haptics.heavy()
        deactivatePlayer()
        if !reduceMotion {
            screenShake()
        }
    }

    private func screenShake() {
        let shakeAmount: CGFloat = 12
        let action = SKAction.sequence([
            SKAction.moveBy(x: shakeAmount, y: 0, duration: 0.03),
            SKAction.moveBy(x: -shakeAmount * 2, y: 0, duration: 0.05),
            SKAction.moveBy(x: shakeAmount, y: 0, duration: 0.03)
        ])
        cameraNode.run(action)
    }

    private func isPlayerOverlappingObstacle() -> Bool {
        let playerFrame = playerNode.frame
        for obstacle in pool.active {
            for piece in obstacle.pieces {
                let pieceFrame = piece.frame
                let worldFrame = CGRect(\n+                    x: obstacle.position.x + pieceFrame.origin.x,\n+                    y: obstacle.position.y + pieceFrame.origin.y,\n+                    width: pieceFrame.width,\n+                    height: pieceFrame.height\n+                )\n+                if playerFrame.intersects(worldFrame) {
                    return true
                }
            }
        }
        return false
    }

    private func handleTitleTouch(_ location: CGPoint) {
        let nodes = nodes(at: location)
        if nodes.contains(where: { $0.name == "play" }) {
            prepareMode()
            stateMachine.transition(to: .playing)
            return
        }
        if nodes.contains(where: { $0.name == "mode" }) {
            mode = mode == .endless ? .daily : .endless
            updateModeLabel()
        }
    }

    private func prepareMode() {
        if mode == .daily {
            dailySeed = dailySeedValue()
            dailyRNG = SplitMix64(seed: dailySeed)
        }
    }

    private func handleGameOverTouch(_ location: CGPoint) {
        let nodes = nodes(at: location)
        if nodes.contains(where: { $0.name == "restart" }) {
            stateMachine.transition(to: .playing)
        }
    }

    private func randomObstacleKind() -> ObstacleKind {
        let roll = randomInt(max: 100)
        if roll < 50 { return .block }
        if roll < 75 { return .gate }
        return .mover
    }

    private func randomLaneX() -> CGFloat {
        let padding: CGFloat = 30
        let x = randomCGFloat()
        return padding + x * (size.width - padding * 2)
    }

    private func randomGapCenter() -> CGFloat {
        let padding: CGFloat = 80
        let x = randomCGFloat()
        return padding + x * (size.width - padding * 2)
    }

    private func randomCGFloat() -> CGFloat {
        switch mode {
        case .endless:
            return CGFloat(Double.random(in: 0...1))
        case .daily:
            return CGFloat(dailyRNG.nextDouble())
        }
    }

    private func randomDouble(in range: ClosedRange<Double>) -> Double {
        let value: Double
        switch mode {
        case .endless:
            value = Double.random(in: 0...1)
        case .daily:
            value = dailyRNG.nextDouble()
        }
        return range.lowerBound + value * (range.upperBound - range.lowerBound)
    }

    private func randomInt(max: Int) -> Int {
        switch mode {
        case .endless:
            return Int.random(in: 0..<max)
        case .daily:
            return Int(dailyRNG.next() % UInt64(max))
        }
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        let padding: CGFloat = 20
        return min(max(x, padding), size.width - padding)
    }

    private func dailySeedValue() -> UInt64 {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let string = formatter.string(from: Date())
        return UInt64(string) ?? 0
    }

    private func dailySeedString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}

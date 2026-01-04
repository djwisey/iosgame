import SpriteKit

enum ObstacleKind: CaseIterable {
    case block
    case gate
    case mover
}

final class ObstacleNode: SKNode {
    let kind: ObstacleKind
    var speed: CGFloat = 200
    var oscillationAmplitude: CGFloat = 0
    var oscillationSpeed: CGFloat = 0
    var baseX: CGFloat = 0
    var nearMissed: Bool = false
    private(set) var pieces: [SKShapeNode] = []

    init(kind: ObstacleKind) {
        self.kind = kind
        super.init()
        name = "obstacle"
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(size: CGSize, sceneWidth: CGFloat, laneX: CGFloat, gapCenter: CGFloat, gapWidth: CGFloat, obstacleSize: CGSize, categoryMask: UInt32) {
        removeAllChildren()
        pieces.removeAll()
        nearMissed = false
        position = CGPoint(x: laneX, y: size.height + obstacleSize.height)
        baseX = laneX

        switch kind {
        case .block:
            let block = makeBlock(size: obstacleSize, categoryMask: categoryMask)
            addChild(block)
            pieces = [block]
            oscillationAmplitude = 0
            oscillationSpeed = 0
        case .gate:
            position = CGPoint(x: sceneWidth / 2, y: size.height + obstacleSize.height)
            let halfGap = gapWidth / 2
            let leftWidth = max(20, gapCenter - halfGap)
            let rightWidth = max(20, sceneWidth - (gapCenter + halfGap))
            let left = makeBlock(size: CGSize(width: leftWidth, height: obstacleSize.height), categoryMask: categoryMask)
            left.position = CGPoint(x: -sceneWidth / 2 + leftWidth / 2, y: 0)
            let right = makeBlock(size: CGSize(width: rightWidth, height: obstacleSize.height), categoryMask: categoryMask)
            right.position = CGPoint(x: sceneWidth / 2 - rightWidth / 2, y: 0)
            addChild(left)
            addChild(right)
            pieces = [left, right]
            oscillationAmplitude = 0
            oscillationSpeed = 0
        case .mover:
            let block = makeBlock(size: obstacleSize, categoryMask: categoryMask)
            addChild(block)
            pieces = [block]
            oscillationAmplitude = min(size.width * 0.25, 120)
            oscillationSpeed = 2.0
        }
    }

    private func makeBlock(size: CGSize, categoryMask: UInt32) -> SKShapeNode {
        let node = SKShapeNode(rectOf: size, cornerRadius: 8)
        node.fillColor = .systemPink
        node.strokeColor = .clear
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.categoryBitMask = categoryMask
        body.contactTestBitMask = 0
        body.collisionBitMask = 0
        node.physicsBody = body
        return node
    }
}

final class ObstaclePool {
    private var available: [ObstacleKind: [ObstacleNode]] = [:]
    private(set) var active: [ObstacleNode] = []

    init() {
        ObstacleKind.allCases.forEach { available[$0] = [] }
    }

    func dequeue(kind: ObstacleKind) -> ObstacleNode {
        if var pool = available[kind], !pool.isEmpty {
            let node = pool.removeLast()
            available[kind] = pool
            return node
        }
        return ObstacleNode(kind: kind)
    }

    func enqueue(_ node: ObstacleNode) {
        node.removeFromParent()
        active.removeAll { $0 == node }
        available[node.kind, default: []].append(node)
    }

    func activate(_ node: ObstacleNode) {
        active.append(node)
    }

    func reset() {
        for node in active {
            enqueue(node)
        }
        active.removeAll()
    }
}

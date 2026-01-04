import Foundation
import SpriteKit

struct TrailStyle {
    let name: String
    let color: SKColor
    let birthRate: CGFloat
    let particleSize: CGFloat
    let speed: CGFloat
}

final class ScoreManager {
    static let shared = ScoreManager()

    private let bestKey = "bestScore"
    private let selectedTrailKey = "selectedTrailStyle"
    private let unlockedTrailsKey = "unlockedTrailStyles"
    private let runCountKey = "runCount"

    private(set) var score: Int = 0
    private(set) var bestScore: Int
    private(set) var unlockedTrailIndices: Set<Int>
    private(set) var selectedTrailIndex: Int
    private(set) var runCount: Int

    let trailUnlockThresholds: [Int] = [0, 1000, 2500, 5000, 10000]

    let trailStyles: [TrailStyle] = [
        TrailStyle(name: "Default", color: .white, birthRate: 90, particleSize: 6, speed: 40),
        TrailStyle(name: "Azure", color: .systemTeal, birthRate: 120, particleSize: 7, speed: 50),
        TrailStyle(name: "Violet", color: .systemPurple, birthRate: 140, particleSize: 8, speed: 60),
        TrailStyle(name: "Gold", color: .systemYellow, birthRate: 160, particleSize: 9, speed: 70),
        TrailStyle(name: "Ruby", color: .systemRed, birthRate: 180, particleSize: 10, speed: 80)
    ]

    private init() {
        let defaults = UserDefaults.standard
        bestScore = defaults.integer(forKey: bestKey)
        selectedTrailIndex = defaults.integer(forKey: selectedTrailKey)
        runCount = defaults.integer(forKey: runCountKey)
        if let stored = defaults.array(forKey: unlockedTrailsKey) as? [Int] {
            unlockedTrailIndices = Set(stored)
        } else {
            unlockedTrailIndices = [0]
        }
        if selectedTrailIndex >= trailStyles.count {
            selectedTrailIndex = 0
        }
    }

    func resetScore() {
        score = 0
    }

    func add(points: Int) {
        score += points
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: bestKey)
            updateTrailUnlocks(for: bestScore)
        }
    }

    func finalizeRun() {
        runCount += 1
        UserDefaults.standard.set(runCount, forKey: runCountKey)
    }

    func updateTrailUnlocks(for score: Int) {
        var unlocked = unlockedTrailIndices
        for (index, threshold) in trailUnlockThresholds.enumerated() {
            if score >= threshold {
                unlocked.insert(index)
            }
        }
        if unlocked != unlockedTrailIndices {
            unlockedTrailIndices = unlocked
            UserDefaults.standard.set(Array(unlocked), forKey: unlockedTrailsKey)
            if let highest = unlocked.max() {
                selectedTrailIndex = highest
                UserDefaults.standard.set(selectedTrailIndex, forKey: selectedTrailKey)
            }
        }
    }

    func selectTrail(index: Int) {
        guard unlockedTrailIndices.contains(index) else { return }
        selectedTrailIndex = index
        UserDefaults.standard.set(selectedTrailIndex, forKey: selectedTrailKey)
    }

    func currentTrailStyle() -> TrailStyle {
        trailStyles[min(selectedTrailIndex, trailStyles.count - 1)]
    }
}

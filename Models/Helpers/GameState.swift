import Foundation

enum GamePhase: String {
    case title
    case playing
    case gameOver
}

final class GameStateMachine {
    private(set) var phase: GamePhase = .title
    var onChange: ((GamePhase) -> Void)?

    func transition(to newPhase: GamePhase) {
        guard newPhase != phase else { return }
        phase = newPhase
        onChange?(newPhase)
    }
}

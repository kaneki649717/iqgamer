import Foundation
import SwiftUI
import BoardCore

/// 一局棋的会话：人机轮流、后台 AI、悔棋快照、提示、终局文本。
/// 7 种棋的具体状态都存在这里，UI 按棋种取用。
@MainActor
final class GameSession: ObservableObject {
    let gameID: GameID

    @Published var difficulty: AIDifficulty = .medium
    @Published var humanFirst: Bool = true
    @Published var goBoardSize: Int = 9
    @Published private(set) var aiThinking = false
    @Published private(set) var resultText: String?
    @Published private(set) var hintDescription: String?
    @Published private(set) var sessionPly = 0

    // 各棋状态（UI 直接绑定渲染）
    @Published var go = GoGame()
    @Published var shogi = Shogi()
    @Published var xiangqi = Xiangqi()
    @Published var chess = Chess()
    @Published var draughts = Draughts()
    @Published var gomoku = Gomoku()
    @Published var reversi = Reversi()

    // 悔棋快照（值语义，直接存整盘）
    var goHistory: [GoGame] = []
    var shogiHistory: [Shogi] = []
    var xiangqiHistory: [Xiangqi] = []
    var chessHistory: [Chess] = []
    var draughtsHistory: [Draughts] = []
    var gomokuHistory: [Gomoku] = []
    var reversiHistory: [Reversi] = []

    private var generation = 0

    init(gameID: GameID) {
        self.gameID = gameID
        if gameID == .go {
            go = GoGame(boardSize: goBoardSize)
        }
    }

    // MARK: - 基本查询

    var humanColor: Int { humanFirst ? 0 : 1 }

    var humanColorName: String {
        switch gameID {
        case .go, .gomoku, .reversi: return humanFirst ? "执黑" : "执白"
        case .xiangqi: return humanFirst ? "执红" : "执黑"
        case .chess, .draughts: return humanFirst ? "执白" : "执黑"
        case .shogi: return humanFirst ? "先手" : "后手"
        }
    }

    var currentPlayer: Int {
        switch gameID {
        case .go: return go.currentPlayer
        case .shogi: return shogi.currentPlayer
        case .xiangqi: return xiangqi.currentPlayer
        case .chess: return chess.currentPlayer
        case .draughts: return draughts.currentPlayer
        case .gomoku: return gomoku.currentPlayer
        case .reversi: return reversi.currentPlayer
        }
    }

    var isOver: Bool {
        switch gameID {
        case .go: return go.isOver
        case .shogi: return shogi.isOver
        case .xiangqi: return xiangqi.isOver
        case .chess: return chess.isOver
        case .draughts: return draughts.isOver
        case .gomoku: return gomoku.isOver
        case .reversi: return reversi.isOver
        }
    }

    var canUndo: Bool {
        switch gameID {
        case .go: return !goHistory.isEmpty
        case .shogi: return !shogiHistory.isEmpty
        case .xiangqi: return !xiangqiHistory.isEmpty
        case .chess: return !chessHistory.isEmpty
        case .draughts: return !draughtsHistory.isEmpty
        case .gomoku: return !gomokuHistory.isEmpty
        case .reversi: return !reversiHistory.isEmpty
        }
    }

    private var currentPlayerIsHuman: Bool {
        !isOver && currentPlayer == humanColor
    }

    // MARK: - 认输 / 清除结果

    func resign() {
        guard !isOver else { return }
        resultText = currentPlayerIsHuman ? "你认输了" : "AI 认输 🎉"
    }

    /// 复盘模式：清除结果浮层（不重开）
    func clearResult() {
        resultText = nil
    }

    // MARK: - 新对局 / 悔棋

    func newGame() {
        generation += 1
        aiThinking = false
        resultText = nil
        hintDescription = nil
        sessionPly = 0
        go = GoGame(boardSize: goBoardSize)
        shogi = Shogi()
        xiangqi = Xiangqi()
        chess = Chess()
        draughts = Draughts()
        gomoku = Gomoku()
        reversi = Reversi()
        goHistory = []; shogiHistory = []; xiangqiHistory = []
        chessHistory = []; draughtsHistory = []; gomokuHistory = []; reversiHistory = []
        scheduleAIIfNeeded()
    }

    func undo() {
        generation += 1
        aiThinking = false
        resultText = nil
        hintDescription = nil
        // 连续回退到「轮到人」的局面
        var guardCounter = 0
        while guardCounter < 2 {
            guardCounter += 1
            let restored: Bool
            switch gameID {
            case .go:
                if let prev = goHistory.popLast() { go = prev; restored = true } else { restored = false }
            case .shogi:
                if let prev = shogiHistory.popLast() { shogi = prev; restored = true } else { restored = false }
            case .xiangqi:
                if let prev = xiangqiHistory.popLast() { xiangqi = prev; restored = true } else { restored = false }
            case .chess:
                if let prev = chessHistory.popLast() { chess = prev; restored = true } else { restored = false }
            case .draughts:
                if let prev = draughtsHistory.popLast() { draughts = prev; restored = true } else { restored = false }
            case .gomoku:
                if let prev = gomokuHistory.popLast() { gomoku = prev; restored = true } else { restored = false }
            case .reversi:
                if let prev = reversiHistory.popLast() { reversi = prev; restored = true } else { restored = false }
            }
            sessionPly = max(0, sessionPly - 1)
            if !restored { break }
            if currentPlayerIsHuman { break }
        }
    }

    private func pushSnapshot() {
        switch gameID {
        case .go: goHistory.append(go)
        case .shogi: shogiHistory.append(shogi)
        case .xiangqi: xiangqiHistory.append(xiangqi)
        case .chess: chessHistory.append(chess)
        case .draughts: draughtsHistory.append(draughts)
        case .gomoku: gomokuHistory.append(gomoku)
        case .reversi: reversiHistory.append(reversi)
        }
    }

    // MARK: - 人类走子（UI 调用，按棋种）

    func playGo(_ move: GoGame.GoMove) { humanMove { $0.go.play(move) } }
    func playShogi(_ move: Shogi.ShogiMove) { humanMove { $0.shogi.play(move) } }
    func playXiangqi(_ move: Xiangqi.XiangqiMove) { humanMove { $0.xiangqi.play(move) } }
    func playChess(_ move: Chess.ChessMove) { humanMove { $0.chess.play(move) } }
    func playDraughts(_ move: Draughts.DraughtsMove) { humanMove { $0.draughts.play(move) } }
    func playGomoku(_ move: Gomoku.GomokuMove) { humanMove { $0.gomoku.play(move) } }
    func playReversi(_ move: Reversi.ReversiMove) { humanMove { $0.reversi.play(move) } }

    private func humanMove(_ play: (GameSession) throws -> Void) {
        guard currentPlayerIsHuman, !aiThinking else { return }
        hintDescription = nil
        pushSnapshot()
        do {
            try play(self)
            sessionPly += 1
        } catch {
            popSnapshot()
            return
        }
        updateResult()
        scheduleAIIfNeeded()
    }

    private func popSnapshot() {
        switch gameID {
        case .go: if !goHistory.isEmpty { go = goHistory.removeLast() }
        case .shogi: if !shogiHistory.isEmpty { shogi = shogiHistory.removeLast() }
        case .xiangqi: if !xiangqiHistory.isEmpty { xiangqi = xiangqiHistory.removeLast() }
        case .chess: if !chessHistory.isEmpty { chess = chessHistory.removeLast() }
        case .draughts: if !draughtsHistory.isEmpty { draughts = draughtsHistory.removeLast() }
        case .gomoku: if !gomokuHistory.isEmpty { gomoku = gomokuHistory.removeLast() }
        case .reversi: if !reversiHistory.isEmpty { reversi = reversiHistory.removeLast() }
        }
    }

    // MARK: - AI 走子

    func scheduleAIIfNeeded() {
        guard !isOver, resultText == nil, !currentPlayerIsHuman, !aiThinking else { return }
        aiThinking = true
        generation += 1
        let gen = generation
        let d = difficulty

        func finish(_ apply: @escaping @MainActor () -> Void) {
            Task.detached(priority: .userInitiated) { [weak self] in
                await MainActor.run {
                    guard let self, gen == self.generation else {
                        self?.aiThinking = false
                        return
                    }
                    self.pushSnapshot()
                    apply()
                    self.aiThinking = false
                    self.sessionPly += 1
                    self.updateResult()
                    // 若 AI 连走（不会发生）或终局则不再调度
                }
            }
        }

        switch gameID {
        case .go:
            let snap = go
            finish { if let m = GoAI.bestMove(in: snap, difficulty: d).move { try? self.go.play(m) } }
        case .shogi:
            let snap = shogi
            finish { if let m = ShogiAI.bestMove(in: snap, difficulty: d).move { try? self.shogi.play(m) } }
        case .xiangqi:
            let snap = xiangqi
            finish { if let m = XiangqiAI.bestMove(in: snap, difficulty: d).move { try? self.xiangqi.play(m) } }
        case .chess:
            let snap = chess
            finish { if let m = ChessAI.bestMove(in: snap, difficulty: d).move { try? self.chess.play(m) } }
        case .draughts:
            let snap = draughts
            finish { if let m = DraughtsAI.bestMove(in: snap, difficulty: d).move { try? self.draughts.play(m) } }
        case .gomoku:
            let snap = gomoku
            finish { if let m = GomokuAI.bestMove(in: snap, difficulty: d).move { try? self.gomoku.play(m) } }
        case .reversi:
            let snap = reversi
            finish { if let m = ReversiAI.bestMove(in: snap, difficulty: d).move { try? self.reversi.play(m) } }
        }
    }

    // MARK: - 提示

    func requestHint() {
        guard currentPlayerIsHuman, !aiThinking else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let gid = await self.gameID
            let desc: String?
            switch gid {
            case .go:
                let snap = await self.go
                desc = GoAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .goMove($0), goSize: snap.boardSize) }
            case .shogi:
                let snap = await self.shogi
                desc = ShogiAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .shogiMove($0), goSize: 19) }
            case .xiangqi:
                let snap = await self.xiangqi
                desc = XiangqiAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .xiangqiMove($0), goSize: 19) }
            case .chess:
                let snap = await self.chess
                desc = ChessAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .chessMove($0), goSize: 19) }
            case .draughts:
                let snap = await self.draughts
                desc = DraughtsAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .draughtsMove($0), goSize: 19) }
            case .gomoku:
                let snap = await self.gomoku
                desc = GomokuAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .gomokuMove($0), goSize: 15) }
            case .reversi:
                let snap = await self.reversi
                desc = ReversiAI.bestMove(in: snap, difficulty: .hard).move.map { Self.describe(gid, .reversiMove($0), goSize: 8) }
            }
            await MainActor.run { self.hintDescription = desc }
        }
    }

    // MARK: - 终局文本

    private func updateResult() {
        guard isOver else { resultText = nil; return }
        let s: Double? = {
            switch gameID {
            case .go: return go.score(for: humanColor)
            case .shogi: return shogi.score(for: humanColor)
            case .xiangqi: return xiangqi.score(for: humanColor)
            case .chess: return chess.score(for: humanColor)
            case .draughts: return draughts.score(for: humanColor)
            case .gomoku: return gomoku.score(for: humanColor)
            case .reversi: return reversi.score(for: humanColor)
            }
        }()
        switch s {
        case 1.0: resultText = "你赢了 🎉"
        case 0.0: resultText = "AI 获胜"
        case 0.5: resultText = "和棋"
        default: resultText = "对局结束"
        }
    }

    // MARK: - 着法文字描述

    enum AnyMove {
        case goMove(GoGame.GoMove)
        case shogiMove(Shogi.ShogiMove)
        case xiangqiMove(Xiangqi.XiangqiMove)
        case chessMove(Chess.ChessMove)
        case draughtsMove(Draughts.DraughtsMove)
        case gomokuMove(Gomoku.GomokuMove)
        case reversiMove(Reversi.ReversiMove)
    }

    static let files = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]

    static func describe(_ gid: GameID, _ m: AnyMove, goSize: Int) -> String {
        switch (gid, m) {
        case (.go, .goMove(let mv)):
            if mv.point == 65535 { return "停一手" }
            let p = Int(mv.point)
            return "推荐落子 \(files[p % goSize])\(goSize - p / goSize)"
        case (.gomoku, .gomokuMove(let mv)):
            return "推荐 \(files[Int(mv.square) % 15])\(15 - Int(mv.square) / 15)"
        case (.chess, .chessMove(let mv)):
            let from = files[Int(mv.from) % 8] + "\(8 - Int(mv.from) / 8)"
            let to = files[Int(mv.to) % 8] + "\(8 - Int(mv.to) / 8)"
            return "推荐 \(from)→\(to)"
        case (.xiangqi, .xiangqiMove(let mv)):
            return "推荐 \(Int(mv.from))→\(Int(mv.to))"
        case (.shogi, .shogiMove(let mv)):
            if mv.from == nil { return "推荐打入 \(Int(mv.to))" }
            return "推荐 \(Int(mv.from!))→\(Int(mv.to))"
        case (.draughts, .draughtsMove(let mv)):
            return "推荐 \(mv.path.map(String.init).joined(separator: "→"))"
        case (.reversi, .reversiMove(let mv)):
            if mv.square == 255 { return "推荐：停一手" }
            return "推荐 \(files[Int(mv.square) % 8])\(8 - Int(mv.square) / 8)"
        default: return ""
        }
    }
}

import Foundation

/// 黑白棋（奥赛罗）。
/// 棋盘 8×8，index = row*8+col，bit = 1 << index。玩家 0 = 黑（先手），1 = 白。
/// 无子可下时自动生成「虚着」（square == 255），双方均无子可下时终局。
public struct Reversi: BoardGame {
    public struct ReversiMove: Hashable, Sendable, Comparable {
        public let square: UInt8 // 0..63，255 = 虚着
        public static let pass = ReversiMove(square: 255)
        public static func < (a: ReversiMove, b: ReversiMove) -> Bool { a.square < b.square }
    }

    public private(set) var black: UInt64
    public private(set) var white: UInt64
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    public private(set) var zobristKey: UInt64

    static let zb = Zobrist.table(64, seed: 0xA1B2_C3D4_0001)
    static let zw = Zobrist.table(64, seed: 0xA1B2_C3D4_0002)
    static let zTurn = Zobrist.table(2, seed: 0xA1B2_C3D4_0003)[1]

    public init() {
        black = (1 << 28) | (1 << 35)
        white = (1 << 27) | (1 << 36)
        currentPlayer = 0
        ply = 0
        zobristKey = Reversi.zb[28] ^ Reversi.zb[35] ^ Reversi.zw[27] ^ Reversi.zw[36]
    }

    public func copy() -> Self { self }

    public var blackCount: Int { black.nonzeroBitCount }
    public var whiteCount: Int { white.nonzeroBitCount }

    static func rc(_ sq: UInt8) -> (Int, Int) { (Int(sq) >> 3, Int(sq) & 7) }

    /// 从 sq 出发、玩家 p 落子会翻转哪些子（位掩码）
    func flips(for sq: UInt8, player p: Int) -> UInt64 {
        let (r0, c0) = Reversi.rc(sq)
        let mine = p == 0 ? black : white
        let theirs = p == 0 ? white : black
        var result: UInt64 = 0
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                var r = r0 + dr, c = c0 + dc
                var line: UInt64 = 0
                var found = false
                while r >= 0 && r < 8 && c >= 0 && c < 8 {
                    let bit = UInt64(1) << (r * 8 + c)
                    if theirs & bit != 0 {
                        line |= bit
                    } else {
                        found = (mine & bit != 0)
                        break
                    }
                    r += dr; c += dc
                }
                if found { result |= line }
            }
        }
        return result
    }

    public func legalMoves() -> [ReversiMove] {
        let all = black | white
        var moves: [ReversiMove] = []
        for sq in 0..<64 where all & (1 << sq) == 0 {
            if flips(for: UInt8(sq), player: currentPlayer) != 0 {
                moves.append(.init(square: UInt8(sq)))
            }
        }
        if moves.isEmpty {
            // 当前无子可下 → 对方仍可下则生成虚着
            let oppMoves = movesFor(player: 1 - currentPlayer)
            if !oppMoves.isEmpty { return [.pass] }
        }
        return moves
    }

    func movesFor(player p: Int) -> [ReversiMove] {
        let all = black | white
        var moves: [ReversiMove] = []
        for sq in 0..<64 where all & (1 << sq) == 0 {
            if flips(for: UInt8(sq), player: p) != 0 {
                moves.append(.init(square: UInt8(sq)))
            }
        }
        return moves
    }

    public var isOver: Bool {
        movesFor(player: 0).isEmpty && movesFor(player: 1).isEmpty
    }

    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        let b = Double(blackCount), w = Double(whiteCount)
        let s = player == 0 ? (b - w) : (w - b)
        if s > 0 { return 1 }
        if s < 0 { return 0 }
        return 0.5
    }

    mutating func togglePlayer() {
        zobristKey ^= Self.zTurn
        currentPlayer = 1 - currentPlayer
    }

    public mutating func play(_ move: ReversiMove) throws {
        if isOver { throw MoveError.gameIsOver }
        if move == .pass {
            // 仅当当前玩家确实没有实体着法才可虚着
            if !movesFor(player: currentPlayer).isEmpty { throw MoveError.illegalMove }
            togglePlayer()
            ply += 1
            return
        }
        let sq = move.square
        guard sq < 64 else { throw MoveError.illegalMove }
        let bit = UInt64(1) << sq
        let flipMask = flips(for: sq, player: currentPlayer)
        guard flipMask != 0 else { throw MoveError.illegalMove }

        if currentPlayer == 0 {
            black |= bit
            white &= ~flipMask
            black |= flipMask
            for i in 0..<64 where flipMask & (1 << i) != 0 {
                zobristKey ^= Self.zw[i] ^ Self.zb[i]
            }
            zobristKey ^= Self.zb[Int(sq)]
        } else {
            white |= bit
            black &= ~flipMask
            white |= flipMask
            for i in 0..<64 where flipMask & (1 << i) != 0 {
                zobristKey ^= Self.zb[i] ^ Self.zw[i]
            }
            zobristKey ^= Self.zw[Int(sq)]
        }
        togglePlayer()
        ply += 1
    }

    public func evaluate() -> Double {
        let all = black | white
        let empties = 64 - all.nonzeroBitCount
        let me = currentPlayer == 0 ? black : white
        let opp = currentPlayer == 0 ? white : black

        var score = 0.0

        // 行动力
        let myMob = Double(mobility(for: currentPlayer))
        let oppMob = Double(mobility(for: 1 - currentPlayer))
        score += (myMob - oppMob) * 0.35

        // 角与角邻
        for corner in Self.cornerSquares {
            let bit = UInt64(1) << corner
            if me & bit != 0 { score += 25 }
            else if opp & bit != 0 { score -= 25 }
            else if all & bit == 0 {
                // 空角旁的危险位置
                for x in Self.xsq[corner]! {
                    let xb = UInt64(1) << x
                    if me & xb != 0 { score -= 9 }
                    else if opp & xb != 0 { score += 9 }
                }
                for c in Self.csq[corner]! {
                    let cb = UInt64(1) << c
                    if me & cb != 0 { score -= 4 }
                    else if opp & cb != 0 { score += 4 }
                }
            }
        }

        // 后期子力差
        let discDiff = Double(me.nonzeroBitCount - opp.nonzeroBitCount)
        if empties <= 14 {
            score += discDiff * 1.6
        } else if empties <= 24 {
            score += discDiff * 0.5
        }

        return score
    }

    func mobility(for p: Int) -> Int {
        let all = black | white
        var count = 0
        for sq in 0..<64 where all & (1 << sq) == 0 {
            if flips(for: UInt8(sq), player: p) != 0 { count += 1 }
        }
        return count
    }

    static let cornerSquares: [UInt8] = [0, 7, 56, 63]
    /// 角 → X 位（对角相邻）
    static let xsq: [UInt8: [UInt8]] = [0: [9], 7: [14], 56: [49], 63: [54]]
    /// 角 → C 位（直邻）
    static let csq: [UInt8: [UInt8]] = [0: [1, 8], 7: [6, 15], 56: [48, 57], 63: [55, 62]]
}

/// 黑白棋 AI（通用 α-β 搜索）
public enum ReversiAI {
    public static func bestMove(in game: Reversi, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<Reversi.ReversiMove> {
        let profile = DifficultyProfile.for(difficulty, depthScale: 1.6)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

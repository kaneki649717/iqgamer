import Foundation

/// 将棋。
/// 棋盘 9×9，index = row*9+col；row 0 = 后手底线（rank1），row 8 = 先手底线（rank9）。
/// 玩家 0 = 先手（row 向减小前进），1 = 后手。
/// 棋子编码：低 4 位类型 1王 2飛 3角 4金 5銀 6桂 7香 8歩；bit4(0x10)=成；bit5(0x20)=后手。
/// 初始：row0 后手底线、row1 后手飛/角、row2 后手歩、row6 先手歩、row7 先手飛/角、row8 先手底线。
public struct Shogi: BoardGame {
    public struct ShogiMove: Hashable, Sendable, Comparable {
        public let from: UInt8?   // nil = 打入
        public let to: UInt8
        public let promote: Bool
        public let drop: UInt8?   // 打入的原始类型（2...8）
        public init(from: UInt8?, to: UInt8, promote: Bool = false, drop: UInt8? = nil) {
            self.from = from
            self.to = to
            self.promote = promote
            self.drop = drop
        }
        public static func < (a: ShogiMove, b: ShogiMove) -> Bool {
            let af = a.from ?? 255, bf = b.from ?? 255
            if af != bf { return af < bf }
            if a.to != b.to { return a.to < b.to }
            if a.promote != b.promote { return !a.promote && b.promote }
            return (a.drop ?? 0) < (b.drop ?? 0)
        }
    }

    public private(set) var board: [UInt8]      // 81 格
    public private(set) var hand: [[Int]]       // [player][type 2..8]
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    public private(set) var zobristKey: UInt64
    var posCounts: [UInt64: Int]                // 千日手计数

    public init() {
        board = Array(repeating: 0, count: 81)
        hand = [Array(repeating: 0, count: 9), Array(repeating: 0, count: 9)]
        let back: [UInt8] = [7, 6, 5, 4, 1, 4, 5, 6, 7] // col0..8 = 香桂銀金王金銀桂香
        for c in 0..<9 {
            board[c] = 0b100000 | back[c]       // 后手底线 row0
            board[18 + c] = 0b100000 | 8        // 后手歩 row2
            board[54 + c] = 8                   // 先手歩 row6
            board[72 + c] = back[c]             // 先手底线 row8
        }
        board[70] = 2                            // 先手飛 2八 (row7 col7)
        board[64] = 3                            // 先手角 8八 (row7 col1)
        board[10] = 0b100000 | 2                 // 后手飛 8二 (row1 col1)
        board[16] = 0b100000 | 3                 // 后手角 2二 (row1 col7)
        currentPlayer = 0
        ply = 0
        let k = Shogi.computeKey(board: board, hand: hand, player: currentPlayer)
        zobristKey = k
        posCounts = [k: 1]
    }

    /// 测试工厂
    init(board: [UInt8], hand: [[Int]], player: Int) {
        self.board = board
        self.hand = hand
        self.currentPlayer = player
        self.ply = 0
        let k = Shogi.computeKey(board: board, hand: hand, player: player)
        self.zobristKey = k
        self.posCounts = [k: 1]
    }

    public func copy() -> Self { self }

    // MARK: - 工具

    @inline(__always) public static func typeOf(_ p: UInt8) -> UInt8 { p & 0b1111 }
    @inline(__always) public static func isPromoted(_ p: UInt8) -> Bool { p & 0b10000 != 0 }
    @inline(__always) public static func colorOf(_ p: UInt8) -> Int { p & 0b100000 != 0 ? 1 : 0 }
    static func rc(_ sq: Int) -> (Int, Int) { (sq / 9, sq % 9) }

    /// 价值（兵=1.0）
    static func value(_ p: UInt8) -> Double {
        let t = typeOf(p)
        if isPromoted(p) {
            switch t {
            case 2: return 12.0
            case 3: return 9.5
            default: return 5.5 // と/成銀/成桂/成香 ≈ 金
            }
        }
        switch t {
        case 1: return 100
        case 2: return 10.0
        case 3: return 8.0
        case 4: return 5.5
        case 5: return 5.0
        case 6: return 3.5
        case 7: return 3.0
        case 8: return 1.0
        default: return 0
        }
    }

    // MARK: - Zobrist

    static let zP: [[[UInt64]]] = {
        var outer: [[[UInt64]]] = []
        for pl in 0..<2 {
            var perType: [[UInt64]] = []
            for t in 0..<18 {
                perType.append(Zobrist.table(81, seed: UInt64(0x510C_0001) ^ (UInt64(pl) << 32) ^ UInt64(t) * 0x9E37))
            }
            outer.append(perType)
        }
        return outer
    }()
    static let zHand: [[[UInt64]]] = {
        var outer: [[[UInt64]]] = []
        for pl in 0..<2 {
            var perType: [[UInt64]] = []
            for t in 0..<9 {
                perType.append(Zobrist.table(19, seed: UInt64(0x4E11_0002) ^ (UInt64(pl) << 32) ^ UInt64(t) * 0x51F1))
            }
            outer.append(perType)
        }
        return outer
    }()
    static let zTurn = Zobrist.table(2, seed: 0x71A2_0003)[1]

    static func computeKey(board: [UInt8], hand: [[Int]], player: Int) -> UInt64 {
        var k: UInt64 = 0
        for (sq, p) in board.enumerated() where p != 0 {
            let t = Int(typeOf(p))
            let idx = t + (isPromoted(p) ? 9 : 0)
            k ^= zP[colorOf(p)][idx][sq]
        }
        for pl in 0..<2 {
            for t in 2...8 {
                let cnt = hand[pl][t]
                if cnt > 0 { k ^= zHand[pl][t][min(cnt, 18)] }
            }
        }
        if player == 1 { k ^= zTurn }
        return k
    }

    // MARK: - 攻击几何（用于将军判定）

    /// 棋子 p 从 a 是否攻击 b（滑子检查路径为空；不考虑打入）
    func pieceAttacks(_ p: UInt8, from a: Int, to b: Int) -> Bool {
        let (ra, ca) = Shogi.rc(a)
        let (rb, cb) = Shogi.rc(b)
        let dr = rb - ra, dc = cb - ca
        if dr == 0 && dc == 0 { return false }
        let f = Shogi.colorOf(p) == 0 ? -1 : 1
        let t = Shogi.typeOf(p)
        let promo = Shogi.isPromoted(p)

        func unitStep(_ dirs: [(Int, Int)]) -> Bool {
            dirs.contains { $0.0 == dr && $0.1 == dc }
        }
        func slide(_ dirs: [(Int, Int)]) -> Bool {
            if dr != 0 && dc != 0 && abs(dr) != abs(dc) { return false }
            let sr = dr == 0 ? 0 : (dr > 0 ? 1 : -1)
            let sc = dc == 0 ? 0 : (dc > 0 ? 1 : -1)
            let ok = dirs.contains {
                ($0.0 == 0 ? 0 : ($0.0 > 0 ? 1 : -1)) == sr &&
                ($0.1 == 0 ? 0 : ($0.1 > 0 ? 1 : -1)) == sc
            }
            guard ok else { return false }
            var r = ra + sr, c = ca + sc
            while r != rb || c != cb {
                if board[r * 9 + c] != 0 { return false }
                r += sr; c += sc
            }
            return true
        }

        let orth = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diag = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        let goldDirs = [(f, 0), (f, -1), (f, 1), (0, -1), (0, 1), (-f, 0)]

        switch (t, promo) {
        case (1, _): return unitStep(orth + diag)
        case (2, false): return slide(orth)
        case (2, true): return slide(orth) || unitStep(diag)
        case (3, false): return slide(diag)
        case (3, true): return slide(diag) || unitStep(orth)
        case (4, _), (5, true), (6, true), (7, true), (8, true): return unitStep(goldDirs)
        case (5, false): return unitStep([(f, 0), (f, -1), (f, 1), (-f, -1), (-f, 1)])
        case (6, false): return unitStep([(2 * f, -1), (2 * f, 1)])
        case (7, false): return slide([(f, 0)])
        case (8, false): return unitStep([(f, 0)])
        default: return false
        }
    }

    /// sq 是否被 player 攻击
    func attacked(_ sq: Int, by player: Int) -> Bool {
        for (i, p) in board.enumerated() where p != 0 && Shogi.colorOf(p) == player {
            if pieceAttacks(p, from: i, to: sq) { return true }
        }
        return false
    }

    func kingSquare(_ player: Int) -> Int? {
        let target: UInt8 = player == 0 ? 1 : (0b100000 | 1)
        for (i, p) in board.enumerated() where p == target { return i }
        return nil
    }

    public var isInCheck: Bool {
        guard let ks = kingSquare(currentPlayer) else { return false }
        return attacked(ks, by: 1 - currentPlayer)
    }

    // MARK: - 走法生成

    /// 走法规格：方向 + 是否滑行
    private func moveSpec(_ p: UInt8) -> [((Int, Int), Bool)] {
        let f = Shogi.colorOf(p) == 0 ? -1 : 1
        let t = Shogi.typeOf(p)
        let promo = Shogi.isPromoted(p)
        let orth: [((Int, Int), Bool)] = [((1, 0), false), ((-1, 0), false), ((0, 1), false), ((0, -1), false)]
        let diag: [((Int, Int), Bool)] = [((1, 1), false), ((1, -1), false), ((-1, 1), false), ((-1, -1), false)]
        let orthS: [((Int, Int), Bool)] = [((1, 0), true), ((-1, 0), true), ((0, 1), true), ((0, -1), true)]
        let diagS: [((Int, Int), Bool)] = [((1, 1), true), ((1, -1), true), ((-1, 1), true), ((-1, -1), true)]
        let gold: [((Int, Int), Bool)] = [((f, 0), false), ((f, -1), false), ((f, 1), false), ((0, -1), false), ((0, 1), false), ((-f, 0), false)]

        switch (t, promo) {
        case (1, _): return orth + diag
        case (2, false): return orthS
        case (2, true): return orthS + diag
        case (3, false): return diagS
        case (3, true): return diagS + orth
        case (4, _), (5, true), (6, true), (7, true), (8, true): return gold
        case (5, false): return [((f, 0), false), ((f, -1), false), ((f, 1), false), ((-f, -1), false), ((-f, 1), false)]
        case (6, false): return [((2 * f, -1), false), ((2 * f, 1), false)]
        case (7, false): return [((f, 0), true)]
        case (8, false): return [((f, 0), false)]
        default: return []
        }
    }

    public func legalMoves() -> [ShogiMove] {
        var pseudo: [ShogiMove] = []
        appendBoardMoves(to: &pseudo)
        appendDrops(to: &pseudo)
        var legal: [ShogiMove] = []
        for m in pseudo {
            var c = self
            c.forcePlay(m)
            let mover = 1 - c.currentPlayer
            guard let ks = c.kingSquare(mover) else { continue }
            if c.attacked(ks, by: c.currentPlayer) { continue }
            // 打歩诘：打入的歩直接将死对方 → 非法
            if m.from == nil, m.drop == 8, c.isInCheck, c.legalMoves().isEmpty { continue }
            legal.append(m)
        }
        return legal
    }

    private func appendBoardMoves(to moves: inout [ShogiMove]) {
        let me = currentPlayer
        for sq in 0..<81 {
            let p = board[sq]
            guard p != 0, Shogi.colorOf(p) == me else { continue }
            let (r, c) = Shogi.rc(sq)
            for ((dr, dc), slides) in moveSpec(p) {
                var step = 1
                while true {
                    let nr = r + dr * step, nc = c + dc * step
                    if nr < 0 || nr > 8 || nc < 0 || nc > 8 { break }
                    let target = nr * 9 + nc
                    let tp = board[target]
                    if tp == 0 {
                        appendMaybePromo(from: sq, to: target, piece: p, to: &moves)
                    } else {
                        if Shogi.colorOf(tp) != me {
                            appendMaybePromo(from: sq, to: target, piece: p, to: &moves)
                        }
                        break
                    }
                    if !slides { break }
                    step += 1
                }
            }
        }
    }

    /// 目标（或出发点）在敌阵可升变；歩香到最底行、桂到最底两行必须升变
    private func appendMaybePromo(from: Int, to: Int, piece: UInt8, to moves: inout [ShogiMove]) {
        let me = currentPlayer
        let zone = me == 0 ? (0...2) : (6...8)
        let canPromote = !Shogi.isPromoted(piece) && Shogi.typeOf(piece) != 1 &&
            (zone.contains(Shogi.rc(from).0) || zone.contains(Shogi.rc(to).0))
        let t = Shogi.typeOf(piece)
        let lastRow = me == 0 ? 0 : 8
        let toRow = Shogi.rc(to).0
        let mustPromote = canPromote &&
            (((t == 8 || t == 7) && toRow == lastRow) ||
             (t == 6 && (me == 0 ? toRow <= 1 : toRow >= 7)))
        if mustPromote {
            moves.append(ShogiMove(from: UInt8(from), to: UInt8(to), promote: true))
        } else if canPromote {
            moves.append(ShogiMove(from: UInt8(from), to: UInt8(to), promote: true))
            moves.append(ShogiMove(from: UInt8(from), to: UInt8(to)))
        } else {
            moves.append(ShogiMove(from: UInt8(from), to: UInt8(to)))
        }
    }

    private func appendDrops(to moves: inout [ShogiMove]) {
        let me = currentPlayer
        for t in 2...8 where hand[me][t] > 0 {
            for sq in 0..<81 where board[sq] == 0 {
                if t == 8 {
                    // 禁二歩：同列已有己方未成歩
                    let col = Shogi.rc(sq).1
                    var nifu = false
                    for r in 0..<9 {
                        let p = board[r * 9 + col]
                        if p != 0, Shogi.colorOf(p) == me, Shogi.typeOf(p) == 8, !Shogi.isPromoted(p) {
                            nifu = true
                            break
                        }
                    }
                    if nifu { continue }
                }
                moves.append(ShogiMove(from: nil, to: UInt8(sq), drop: UInt8(t)))
            }
        }
    }

    // MARK: - 走子

    public mutating func play(_ move: ShogiMove) throws {
        let to = Int(move.to)
        guard to >= 0 && to < 81 else { throw MoveError.illegalMove }
        if let from = move.from {
            guard (0..<81).contains(Int(from)) else { throw MoveError.illegalMove }
            let p = board[Int(from)]
            guard p != 0, Shogi.colorOf(p) == currentPlayer else { throw MoveError.illegalMove }
            guard !Shogi.isPromoted(p) || !move.promote else { throw MoveError.illegalMove }
            if move.promote {
                let zone = currentPlayer == 0 ? (0...2) : (6...8)
                guard zone.contains(Shogi.rc(Int(from)).0) || zone.contains(to / 9) else {
                    throw MoveError.illegalMove
                }
            }
            guard board[to] == 0 || Shogi.colorOf(board[to]) != currentPlayer else { throw MoveError.illegalMove }
        } else {
            guard let drop = move.drop, (2...8).contains(Int(drop)) else { throw MoveError.illegalMove }
            guard hand[currentPlayer][Int(drop)] > 0, board[to] == 0, !move.promote else {
                throw MoveError.illegalMove
            }
        }
        forcePlay(move)
    }

    mutating func forcePlay(_ move: ShogiMove) {
        let me = currentPlayer
        var key = zobristKey
        key ^= Self.zTurn

        if let from = move.from {
            let fromI = Int(from)
            let p = board[fromI]
            let t = Int(Shogi.typeOf(p))
            key ^= Self.zP[me][t + (Shogi.isPromoted(p) ? 9 : 0)][fromI]

            let captured = board[Int(move.to)]
            if captured != 0 {
                let capColor = Shogi.colorOf(captured)
                let capBase = Int(Shogi.typeOf(captured)) // 成子降级：类型位即原始类型
                key ^= Self.zP[capColor][Int(Shogi.typeOf(captured)) + (Shogi.isPromoted(captured) ? 9 : 0)][Int(move.to)]
                let oldCnt = hand[me][capBase]
                let newCnt = oldCnt + 1
                if oldCnt > 0 { key ^= Self.zHand[me][capBase][min(oldCnt, 18)] }
                key ^= Self.zHand[me][capBase][min(newCnt, 18)]
                hand[me][capBase] = newCnt
            }

            let newPromo = move.promote || Shogi.isPromoted(p)
            key ^= Self.zP[me][t + (newPromo ? 9 : 0)][Int(move.to)]
            let typeBits = newPromo ? (0b10000 | UInt8(t)) : UInt8(t)
            board[Int(move.to)] = me == 0 ? typeBits : (0b100000 | typeBits)
            board[fromI] = 0
        } else if let drop = move.drop {
            let t = Int(drop)
            let oldCnt = hand[me][t]
            let newCnt = oldCnt - 1
            key ^= Self.zHand[me][t][min(oldCnt, 18)]
            if newCnt > 0 { key ^= Self.zHand[me][t][min(newCnt, 18)] }
            hand[me][t] = newCnt
            board[Int(move.to)] = me == 0 ? UInt8(t) : (0b100000 | UInt8(t))
            key ^= Self.zP[me][t][Int(move.to)]
        }

        currentPlayer = 1 - currentPlayer
        ply += 1
        zobristKey = key
        posCounts[key, default: 0] += 1
    }

    // MARK: - 终局与评估

    public var isOver: Bool {
        if (posCounts[zobristKey] ?? 0) >= 4 { return true }
        return legalMoves().isEmpty
    }

    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        if legalMoves().isEmpty {
            return currentPlayer == player ? 0.0 : 1.0
        }
        return 0.5 // 千日手
    }

    public func evaluate() -> Double {
        var scores = [0.0, 0.0]
        for (sq, p) in board.enumerated() where p != 0 {
            var v = Shogi.value(p)
            let (r, c) = Shogi.rc(sq)
            let t = Shogi.typeOf(p)
            if t == 8 || t == 7 {
                let advance = Shogi.colorOf(p) == 0 ? (8 - r) : r
                v += Double(advance) * 0.02
            }
            v += (4.0 - abs(4.0 - Double(c))) * 0.015
            scores[Shogi.colorOf(p)] += v
        }
        for pl in 0..<2 {
            for t in 2...8 {
                scores[pl] += Double(hand[pl][t]) * Shogi.valueForHand(UInt8(t))
            }
        }
        let diff = scores[0] - scores[1]
        return currentPlayer == 0 ? diff : -diff
    }

    // MARK: - 搜索钩子

    public func orderHint(for move: ShogiMove) -> Int {
        if move.from == nil { return -50 }
        let victim = board[Int(move.to)]
        let attacker = board[Int(move.from!)]
        var h = 0
        if victim != 0 {
            h = Int((Shogi.value(victim) * 10 - Shogi.value(attacker)) * 10)
        }
        if move.promote { h += 60 }
        return h
    }

    public func isTactical(_ move: ShogiMove) -> Bool {
        move.from != nil && board[Int(move.to)] != 0
    }
}

extension Shogi {
    static func valueForHand(_ t: UInt8) -> Double {
        switch t {
        case 2: return 10.0
        case 3: return 8.0
        case 4: return 5.5
        case 5: return 5.0
        case 6: return 3.5
        case 7: return 3.0
        case 8: return 1.0
        default: return 0
        }
    }
}

/// 将棋 AI
public enum ShogiAI {
    public static func bestMove(in game: Shogi, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<Shogi.ShogiMove> {
        let profile = DifficultyProfile.for(difficulty, depthScale: 0.85)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

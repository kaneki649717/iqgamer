import Foundation

/// 五子棋（自由规则，15×15，长连也算胜）。
/// 玩家 0 = 黑（先手），1 = 白。index = row*15+col。
public struct Gomoku: BoardGame {
    public struct GomokuMove: Hashable, Sendable, Comparable {
        public let square: UInt8 // 0..224
        public init(_ s: UInt8) { square = s }
        public init(row: Int, col: Int) { square = UInt8(row * 15 + col) }
        public var row: Int { Int(square) / 15 }
        public var col: Int { Int(square) % 15 }
        public static func < (a: GomokuMove, b: GomokuMove) -> Bool { a.square < b.square }
    }

    public static let size = 15
    public private(set) var board: [UInt8] // 0 空 1 黑 2 白
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    public private(set) var winner: Int?   // 0/1，nil 未终局
    public private(set) var zobristKey: UInt64

    static let zSide: [UInt64] = Zobrist.table(225 * 2, seed: 0xC0DE_BABE_0001)

    public init() {
        board = Array(repeating: 0, count: 225)
        currentPlayer = 0
        ply = 0
        winner = nil
        zobristKey = 0
    }

    public func copy() -> Self { self }

    static func stoneKey(_ sq: Int, player: Int) -> UInt64 {
        zSide[sq * 2 + player]
    }

    /// 某点落子后是否形成五连及以上（供 play 与威胁检测共用）
    func makesWin(_ sq: Int, player p: Int) -> Bool {
        let r = sq / 15, c = sq % 15
        let color = p + 1
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var count = 1
            var i = 1
            while true {
                let nr = r + dr * i, nc = c + dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || board[nr * 15 + nc] != color { break }
                count += 1; i += 1
            }
            i = 1
            while true {
                let nr = r - dr * i, nc = c - dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || board[nr * 15 + nc] != color { break }
                count += 1; i += 1
            }
            if count >= 5 { return true }
        }
        return false
    }

    public var isOver: Bool { winner != nil || ply == 225 }

    public func score(for player: Int) -> Double? {
        guard let w = winner else { return ply == 225 ? 0.5 : nil }
        return w == player ? 1 : 0
    }

    /// 候选点：已有棋子的切比雪夫距离 ≤ 2 的空点
    public func legalMoves() -> [GomokuMove] {
        if isOver { return [] }
        var cand: [Bool] = Array(repeating: false, count: 225)
        if ply == 0 { return [GomokuMove(112)] } // 天元
        for sq in 0..<225 where board[sq] != 0 {
            let r = sq / 15, c = sq % 15
            for dr in -2...2 {
                for dc in -2...2 {
                    let nr = r + dr, nc = c + dc
                    if nr >= 0 && nr < 15 && nc >= 0 && nc < 15 && board[nr * 15 + nc] == 0 {
                        cand[nr * 15 + nc] = true
                    }
                }
            }
        }
        var moves: [GomokuMove] = []
        for sq in 0..<225 where cand[sq] { moves.append(GomokuMove(UInt8(sq))) }
        return moves
    }

    public mutating func play(_ move: GomokuMove) throws {
        guard !isOver else { throw MoveError.gameIsOver }
        let sq = Int(move.square)
        guard sq >= 0 && sq < 225 && board[sq] == 0 else { throw MoveError.illegalMove }
        board[sq] = UInt8(currentPlayer + 1)
        zobristKey ^= Self.stoneKey(sq, player: currentPlayer)
        if makesWin(sq, player: currentPlayer) {
            winner = currentPlayer
        }
        currentPlayer = 1 - currentPlayer
        ply += 1
    }

    public func evaluate() -> Double {
        let diff = lineScore(player: 0) - lineScore(player: 1)
        return currentPlayer == 0 ? diff : -diff
    }

    /// 对 p 的形势分（从 p 视角）
    /// v1.3 修复：窗口沿整条线滑动评估（旧实现只扫线头一个 6 格窗口，
    /// 导致棋盘第 6 行/列以下全部成为评估盲区，AI 对下半区威胁完全失明）
    func lineScore(player p: Int) -> Double {
        let me = p + 1, op = 2 - p
        var total = 0.0
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for r in 0..<15 {
            for c in 0..<15 {
                for (dr, dc) in dirs {
                    var myCount = 0, opCount = 0
                    var len = 0
                    var rr = r, cc = c
                    while rr >= 0 && rr < 15 && cc >= 0 && cc < 15 && len < 6 {
                        let v = board[rr * 15 + cc]
                        if v == me { myCount += 1 }
                        else if v == op { opCount += 1 }
                        rr += dr; cc += dc; len += 1
                    }
                    if opCount == 0 && myCount > 0 {
                        total += patternValue(myCount, openEnds: openEnds(r: r, c: c, dr: dr, dc: dc, len: len))
                    }
                }
            }
        }
        return total
    }

    /// 窗口两端是否为空（粗略开放度）
    func openEnds(r: Int, c: Int, dr: Int, dc: Int, len: Int) -> Int {
        var ends = 0
        let br = r - dr, bc = c - dc
        if br >= 0 && br < 15 && bc >= 0 && bc < 15 && board[br * 15 + bc] == 0 { ends += 1 }
        let er = r + dr * len, ec = c + dc * len
        if er >= 0 && er < 15 && ec >= 0 && ec < 15 && board[er * 15 + ec] == 0 { ends += 1 }
        return ends
    }

    func patternValue(_ count: Int, openEnds: Int) -> Double {
        switch (count, openEnds) {
        case (5, _): return 1000
        case (_, 0): return 0
        case (4, 2): return 120      // 活四
        case (4, 1): return 25       // 冲四
        case (3, 2): return 30       // 活三
        case (3, 1): return 4
        case (2, 2): return 6
        case (2, 1): return 1
        default: return 0.2
        }
    }

    /// 走子排序：落子增益（我方形成威胁 + 对方威胁拦截）
    public func orderHint(for move: GomokuMove) -> Int {
        let sq = Int(move.square)
        var h = 0
        h += Int(gainAt(sq: sq, player: currentPlayer))
        h += Int(gainAt(sq: sq, player: 1 - currentPlayer)) * 9 / 10
        return h
    }

    func gainAt(sq: Int, player p: Int) -> Double {
        // 模拟落子前后的形势差（只算该点四向）
        let r = sq / 15, c = sq % 15
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var v = 0.0
        for (dr, dc) in dirs {
            var count = 1, block = 0, open = 0
            // 正向
            var i = 1
            while true {
                let nr = r + dr * i, nc = c + dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 { block += 1; break }
                let cell = board[nr * 15 + nc]
                if cell == 0 { open += 1; break }
                if cell == p + 1 { count += 1; i += 1; continue }
                block += 1; break
            }
            // 反向
            i = 1
            var open2 = 0
            while true {
                let nr = r - dr * i, nc = c - dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 { block += 1; break }
                let cell = board[nr * 15 + nc]
                if cell == 0 { open2 += 1; break }
                if cell == p + 1 { count += 1; i += 1; continue }
                block += 1; break
            }
            let ends = open + open2
            v += patternValue(count, openEnds: ends)
        }
        return v
    }

    public func isTactical(_ move: GomokuMove) -> Bool {
        gainAt(sq: Int(move.square), player: currentPlayer) >= 4
    }
}

// MARK: - VCF 算杀（连续冲四取胜搜索，v1.4）

extension Gomoku {
    /// b 盘面上：p 在空点落子即成五的点集合
    static func gomokuWinPoints(_ b: [UInt8], for p: Int) -> [Int] {
        let stone = UInt8(p + 1)
        var result: [Int] = []
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for sq in 0..<225 where b[sq] == 0 {
            let r = sq / 15, c = sq % 15
            for (dr, dc) in dirs {
                var run = 1
                var i = 1
                while true {
                    let nr = r + dr * i, nc = c + dc * i
                    if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || b[nr * 15 + nc] != stone { break }
                    run += 1; i += 1
                }
                i = 1
                while true {
                    let nr = r - dr * i, nc = c - dc * i
                    if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || b[nr * 15 + nc] != stone { break }
                    run += 1; i += 1
                }
                if run >= 5 { result.append(sq); break }
            }
        }
        return result
    }

    /// b 盘面上：p 在 sq 落子是否直接成五
    static func makesFiveOn(_ b: [UInt8], _ sq: Int, _ p: Int) -> Bool {
        let stone = UInt8(p + 1)
        let r = sq / 15, c = sq % 15
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var run = 1
            var i = 1
            while true {
                let nr = r + dr * i, nc = c + dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || b[nr * 15 + nc] != stone { break }
                run += 1; i += 1
            }
            i = 1
            while true {
                let nr = r - dr * i, nc = c - dc * i
                if nr < 0 || nr >= 15 || nc < 0 || nc >= 15 || b[nr * 15 + nc] != stone { break }
                run += 1; i += 1
            }
            if run >= 5 { return true }
        }
        return false
    }

    static func nearStones(_ b: [UInt8], _ sq: Int) -> Bool {
        let r = sq / 15, c = sq % 15
        for dr in -2...2 {
            for dc in -2...2 {
                let nr = r + dr, nc = c + dc
                if nr >= 0 && nr < 15 && nc >= 0 && nc < 15 && b[nr * 15 + nc] != 0 { return true }
            }
        }
        return false
    }

    /// p 的所有「成四着法」：落子后 p 存在成五点（直接成五的另行处理）
    static func fourMovesOn(_ b: [UInt8], for p: Int) -> [(sq: Int, wp: [Int])] {
        var b = b
        var out: [(sq: Int, wp: [Int])] = []
        for sq in 0..<225 where b[sq] == 0 && nearStones(b, sq) {
            guard !makesFiveOn(b, sq, p) else { continue }
            b[sq] = UInt8(p + 1)
            let wp = gomokuWinPoints(b, for: p)
            b[sq] = 0
            if !wp.isEmpty { out.append((sq, wp)) }
        }
        return out
    }

    /// VCF 主搜索：p 连续冲四必胜时返回首着。
    /// 保守剪枝：防守方存在反击成五点的分支一律按失败处理（绝不误报必胜）；节点上限保证手机耗时。
    func vcfFirstMove(player p: Int, maxDepth: Int = 12, nodeLimit: Int = 10000) -> Int? {
        var b = board
        let myStone = UInt8(p + 1)
        let opStone = UInt8((1 - p) + 1)
        var nodes = 0

        func search(_ depth: Int) -> Int? {
            if depth <= 0 { return nil }
            nodes += 1
            if nodes > nodeLimit { return nil }
            // 1) 直接成五
            for sq in 0..<225 where b[sq] == 0 && Gomoku.nearStones(b, sq) {
                if Gomoku.makesFiveOn(b, sq, p) { return sq }
            }
            // 2) 冲四点
            let fours = Gomoku.fourMovesOn(b, for: p)
            for (sq, wp) in fours {
                if wp.count >= 2 { return sq } // 双四（含活四）必胜
                guard let block = wp.first else { continue }
                b[sq] = myStone
                // 防守方若已有成五点（此前的冲四未挡）→ 攻击失败
                if Gomoku.gomokuWinPoints(b, for: 1 - p).isEmpty {
                    b[block] = opStone // 防守被迫唯一堵点
                    let sub = search(depth - 1)
                    b[block] = 0
                    b[sq] = 0
                    if let _ = sub { return sq }
                } else {
                    b[sq] = 0
                }
            }
            return nil
        }

        return search(maxDepth)
    }
}

/// 五子棋 AI
public enum GomokuAI {
    public static func bestMove(in game: Gomoku, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<Gomoku.GomokuMove> {
        // VCF 算杀优先：存在连续冲四必胜序列时直接执行首着（高/超高/天人档启用）
        if difficulty == .hard || difficulty == .veryHard || difficulty == .celestial {
            if let first = game.vcfFirstMove(player: game.currentPlayer) {
                return SearchResult(move: Gomoku.GomokuMove(UInt8(first)), value: 0.99, depth: 0, nodes: 0)
            }
        }
        let profile = DifficultyProfile.for(difficulty, depthScale: 1.4)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

import Foundation

/// 中国象棋。
/// 棋盘 9×10，index = row*9+col；row 0 = 黑方底线（顶部），row 9 = 红方底线（底部）。
/// 玩家 0 = 红（先手，row 向减小前进），1 = 黑。河界位于 row 4 与 row 5 之间。
/// 棋子编码：0 = 空；低 3 位类型 1帥 2仕 3相 4馬 5車 6炮 7兵；bit3(0b1000) = 黑方旗标。
public struct Xiangqi: BoardGame {
    public struct XiangqiMove: Hashable, Sendable, Comparable {
        public let from: UInt8
        public let to: UInt8
        public init(from: UInt8, to: UInt8) {
            self.from = from
            self.to = to
        }
        public static func < (a: XiangqiMove, b: XiangqiMove) -> Bool {
            if a.from != b.from { return a.from < b.from }
            return a.to < b.to
        }
    }

    // MARK: - 状态

    public private(set) var board: [UInt8]          // 90 格
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    public private(set) var halfmoveClock: UInt16   // 无吃子半回合计数（≥120 判和）
    public private(set) var zobristKey: UInt64
    var history: [UInt64]                           // 局面 key 历史（含初始）
    var posCounts: [UInt64: Int]                    // 三次重复局面计数
    var kingSq: (Int, Int)                          // (红帥格, 黑將格)

    // MARK: - 常量

    /// 子力价值（按类型 0..7 索引；帥用大值 1000，正常对局双方抵消）
    static let pieceValues: [Double] = [0, 1000, 2.0, 2.0, 4.0, 9.0, 4.5, 1.0]
    static let horseOffsets = [(2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)]
    static let orthoDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let diagDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    // Zobrist 键表
    static let zPiece: [[UInt64]] = [
        Zobrist.table(7 * 90, seed: 0x10A1_0001),
        Zobrist.table(7 * 90, seed: 0x10A1_0002),
    ]
    static let zSide = Zobrist.table(2, seed: 0x10A1_0003)[1]

    public init() {
        board = Array(repeating: 0, count: 90)
        let back: [UInt8] = [5, 4, 3, 2, 1, 2, 3, 4, 5] // 車馬相仕帥仕相馬車
        for c in 0..<9 {
            board[c] = UInt8(0b1000 | back[c])           // 黑方底线 row 0
            board[81 + c] = back[c]                       // 红方底线 row 9
        }
        board[19] = UInt8(0b1000 | 6)                    // 黑炮 (2,1)
        board[25] = UInt8(0b1000 | 6)                    // 黑炮 (2,7)
        board[64] = 6                                     // 红炮 (7,1)
        board[70] = 6                                     // 红炮 (7,7)
        for c in [0, 2, 4, 6, 8] {
            board[27 + c] = UInt8(0b1000 | 7)            // 黑卒 row 3
            board[54 + c] = 7                             // 红兵 row 6
        }
        currentPlayer = 0
        ply = 0
        halfmoveClock = 0
        kingSq = (85, 4)
        let k = Xiangqi.computeKey(board: board, player: currentPlayer)
        zobristKey = k
        history = [k]
        posCounts = [k: 1]
    }

    /// 测试工厂：直接摆子（编码同上；帥/將位置自动探测）
    init(board: [UInt8], player: Int, halfmove: UInt16 = 0) {
        self.board = board
        self.currentPlayer = player
        self.halfmoveClock = halfmove
        self.ply = 0
        var rk = 85, bk = 4
        for (i, p) in board.enumerated() where Xiangqi.typeOf(p) == 1 {
            if Xiangqi.colorOf(p) == 0 { rk = i } else { bk = i }
        }
        self.kingSq = (rk, bk)
        let k = Xiangqi.computeKey(board: board, player: player)
        self.zobristKey = k
        self.history = [k]
        self.posCounts = [k: 1]
    }

    public func copy() -> Self { self }

    // MARK: - 棋子工具

    @inline(__always) public static func typeOf(_ p: UInt8) -> UInt8 { p & 0b111 }
    @inline(__always) public static func colorOf(_ p: UInt8) -> Int { (p & 0b1000) != 0 ? 1 : 0 }
    static func rc(_ sq: Int) -> (Int, Int) { (sq / 9, sq % 9) }

    /// 九宫：player 0 = rows 7-9 / cols 3-5，player 1 = rows 0-2 / cols 3-5
    static func inPalace(_ sq: Int, player: Int) -> Bool {
        let c = sq % 9
        if c < 3 || c > 5 { return false }
        return player == 0 ? sq >= 63 : sq <= 26
    }

    /// 本方半场（相/象不得过河）：红 rows 5-9，黑 rows 0-4
    static func ownHalf(_ r: Int, player: Int) -> Bool {
        player == 0 ? r >= 5 : r <= 4
    }

    // MARK: - Zobrist

    static func computeKey(board: [UInt8], player: Int) -> UInt64 {
        var k: UInt64 = 0
        for (sq, p) in board.enumerated() where p != 0 {
            k ^= zPiece[colorOf(p)][Int(typeOf(p) - 1) * 90 + sq]
        }
        if player == 1 { k ^= zSide }
        return k
    }

    // MARK: - 攻击检测

    /// sq 是否被 player 一方攻击（将帅照面由 facingKings 单独判定）
    func attacked(_ sq: Int, by player: Int) -> Bool {
        let (r, c) = Xiangqi.rc(sq)
        // 帥/將 正交一步
        let kg: UInt8 = player == 0 ? 1 : (0b1000 | 1)
        for (dr, dc) in Xiangqi.orthoDirs {
            let nr = r + dr, nc = c + dc
            if nr >= 0 && nr < 10 && nc >= 0 && nc < 9 && board[nr * 9 + nc] == kg { return true }
        }
        // 仕/士 斜一格
        let adv: UInt8 = player == 0 ? 2 : (0b1000 | 2)
        for (dr, dc) in Xiangqi.diagDirs {
            let nr = r + dr, nc = c + dc
            if nr >= 0 && nr < 10 && nc >= 0 && nc < 9 && board[nr * 9 + nc] == adv { return true }
        }
        // 相/象 田字：塞象眼、不过河
        let ele: UInt8 = player == 0 ? 3 : (0b1000 | 3)
        for (dr, dc) in Xiangqi.diagDirs {
            let nr = r + 2 * dr, nc = c + 2 * dc
            guard nr >= 0 && nr < 10 && nc >= 0 && nc < 9 else { continue }
            guard board[nr * 9 + nc] == ele, board[(r + dr) * 9 + (c + dc)] == 0 else { continue }
            if Xiangqi.ownHalf(nr, player: player) { return true }
        }
        // 馬 日字：腿在马位沿主方向（|Δ|=2 的分量）一格
        let horse: UInt8 = player == 0 ? 4 : (0b1000 | 4)
        for (dr, dc) in Xiangqi.horseOffsets {
            let hr = r + dr, hc = c + dc
            guard hr >= 0 && hr < 10 && hc >= 0 && hc < 9 else { continue }
            guard board[hr * 9 + hc] == horse else { continue }
            let legR = abs(dr) == 2 ? hr - dr / 2 : hr
            let legC = abs(dc) == 2 ? hc - dc / 2 : hc
            if board[legR * 9 + legC] == 0 { return true }
        }
        // 車 / 炮：正交滑行；第一个子是車即攻击，隔一个炮架后遇炮即攻击
        let chariot: UInt8 = player == 0 ? 5 : (0b1000 | 5)
        let cannon: UInt8 = player == 0 ? 6 : (0b1000 | 6)
        for (dr, dc) in Xiangqi.orthoDirs {
            var nr = r + dr, nc = c + dc
            var screenPassed = false
            while nr >= 0 && nr < 10 && nc >= 0 && nc < 9 {
                let p = board[nr * 9 + nc]
                if p != 0 {
                    if !screenPassed {
                        if p == chariot { return true }
                        screenPassed = true
                    } else {
                        if p == cannon { return true }
                        break
                    }
                }
                nr += dr; nc += dc
            }
        }
        // 兵/卒：向前攻击；过河后可横击
        let pawn: UInt8 = player == 0 ? 7 : (0b1000 | 7)
        let pr = player == 0 ? r + 1 : r - 1
        if pr >= 0 && pr < 10 && board[pr * 9 + c] == pawn { return true }
        let crossed = player == 0 ? r <= 4 : r >= 5
        if crossed {
            if c > 0 && board[r * 9 + c - 1] == pawn { return true }
            if c < 8 && board[r * 9 + c + 1] == pawn { return true }
        }
        return false
    }

    /// 将帅照面：同列且中间无子（等价于飞行将可吃）
    var facingKings: Bool {
        if kingSq.0 % 9 != kingSq.1 % 9 { return false }
        let lo = min(kingSq.0, kingSq.1)
        let hi = max(kingSq.0, kingSq.1)
        var sq = lo + 9
        while sq < hi {
            if board[sq] != 0 { return false }
            sq += 9
        }
        return true
    }

    public var isInCheck: Bool {
        let ks = currentPlayer == 0 ? kingSq.0 : kingSq.1
        return attacked(ks, by: 1 - currentPlayer) || facingKings
    }

    // MARK: - 走法生成

    public func legalMoves() -> [XiangqiMove] {
        var pseudo: [XiangqiMove] = []
        appendPseudoMoves(to: &pseudo)
        var legal: [XiangqiMove] = []
        legal.reserveCapacity(pseudo.count)
        for m in pseudo {
            var c = self
            c.forcePlay(m)
            let mover = 1 - c.currentPlayer
            let ks = mover == 0 ? c.kingSq.0 : c.kingSq.1
            // 走后己方被将或与对方将照面 → 非法
            if !c.attacked(ks, by: c.currentPlayer) && !c.facingKings {
                legal.append(m)
            }
        }
        return legal
    }

    private func appendPseudoMoves(to moves: inout [XiangqiMove]) {
        let me = currentPlayer
        for sq in 0..<90 {
            let p = board[sq]
            guard p != 0, Xiangqi.colorOf(p) == me else { continue }
            let (r, c) = Xiangqi.rc(sq)
            switch Xiangqi.typeOf(p) {
            case 1: appendKingMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 2: appendAdvisorMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 3: appendElephantMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 4: appendHorseMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 5: appendChariotMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 6: appendCannonMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 7: appendPawnMoves(from: sq, r: r, c: c, player: me, to: &moves)
            default: break
            }
        }
    }

    /// 目标格可落子（空或敌子）
    @inline(__always) func canLand(_ t: Int, player: Int) -> Bool {
        let tp = board[t]
        return tp == 0 || Xiangqi.colorOf(tp) != player
    }

    private func appendKingMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.orthoDirs {
            let nr = r + dr, nc = c + dc
            guard nr >= 0 && nr < 10 && nc >= 0 && nc < 9 else { continue }
            let t = nr * 9 + nc
            guard Xiangqi.inPalace(t, player: player), canLand(t, player: player) else { continue }
            moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
        }
    }

    private func appendAdvisorMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.diagDirs {
            let nr = r + dr, nc = c + dc
            guard nr >= 0 && nr < 10 && nc >= 0 && nc < 9 else { continue }
            let t = nr * 9 + nc
            guard Xiangqi.inPalace(t, player: player), canLand(t, player: player) else { continue }
            moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
        }
    }

    private func appendElephantMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.diagDirs {
            let nr = r + 2 * dr, nc = c + 2 * dc
            guard nr >= 0 && nr < 10 && nc >= 0 && nc < 9 else { continue }
            guard Xiangqi.ownHalf(nr, player: player) else { continue }   // 不过河
            guard board[(r + dr) * 9 + (c + dc)] == 0 else { continue }   // 塞象眼
            let t = nr * 9 + nc
            guard canLand(t, player: player) else { continue }
            moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
        }
    }

    private func appendHorseMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.horseOffsets {
            let nr = r + dr, nc = c + dc
            guard nr >= 0 && nr < 10 && nc >= 0 && nc < 9 else { continue }
            // 马腿：主方向（|Δ|=2 的分量）一格
            let legR = abs(dr) == 2 ? r + dr / 2 : r
            let legC = abs(dc) == 2 ? c + dc / 2 : c
            guard board[legR * 9 + legC] == 0 else { continue }           // 蹩马腿
            let t = nr * 9 + nc
            guard canLand(t, player: player) else { continue }
            moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
        }
    }

    private func appendChariotMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.orthoDirs {
            var nr = r + dr, nc = c + dc
            while nr >= 0 && nr < 10 && nc >= 0 && nc < 9 {
                let t = nr * 9 + nc
                let tp = board[t]
                if tp == 0 {
                    moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
                } else {
                    if Xiangqi.colorOf(tp) != player {
                        moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
                    }
                    break
                }
                nr += dr; nc += dc
            }
        }
    }

    private func appendCannonMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        for (dr, dc) in Xiangqi.orthoDirs {
            var nr = r + dr, nc = c + dc
            var screen = false
            while nr >= 0 && nr < 10 && nc >= 0 && nc < 9 {
                let t = nr * 9 + nc
                let tp = board[t]
                if !screen {
                    if tp == 0 {
                        moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
                    } else {
                        screen = true                                     // 炮架
                    }
                } else if tp != 0 {
                    if Xiangqi.colorOf(tp) != player {
                        moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))   // 隔子打
                    }
                    break
                }
                nr += dr; nc += dc
            }
        }
    }

    private func appendPawnMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [XiangqiMove]) {
        let dir = player == 0 ? -1 : 1
        let nr = r + dir
        if nr >= 0 && nr < 10 {
            let t = nr * 9 + c
            if canLand(t, player: player) {
                moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
            }
        }
        // 过河后可横移
        let crossed = player == 0 ? r <= 4 : r >= 5
        if crossed {
            for dc in [-1, 1] {
                let nc = c + dc
                guard nc >= 0 && nc < 9 else { continue }
                let t = r * 9 + nc
                if canLand(t, player: player) {
                    moves.append(XiangqiMove(from: UInt8(sq), to: UInt8(t)))
                }
            }
        }
    }

    // MARK: - 走子

    public mutating func play(_ move: XiangqiMove) throws {
        let from = Int(move.from), to = Int(move.to)
        guard from >= 0 && from < 90 && to >= 0 && to < 90 else { throw MoveError.illegalMove }
        let p = board[from]
        guard p != 0, Xiangqi.colorOf(p) == currentPlayer else { throw MoveError.illegalMove }
        let tp = board[to]
        guard tp == 0 || Xiangqi.colorOf(tp) != currentPlayer else { throw MoveError.illegalMove }
        guard Xiangqi.typeOf(tp) != 1 else { throw MoveError.illegalMove }   // 帥/將不可被吃
        forcePlay(move)
    }

    /// 内部快速走子（legalMoves 生成的着法必合法；zobrist 增量维护）
    private mutating func forcePlay(_ move: XiangqiMove) {
        let from = Int(move.from), to = Int(move.to)
        let moving = board[from]
        let myType = Xiangqi.typeOf(moving)
        let me = currentPlayer
        var key = zobristKey
        key ^= Self.zSide

        let captured = board[to]
        if captured != 0 {
            key ^= Self.zPiece[Xiangqi.colorOf(captured)][Int(Xiangqi.typeOf(captured) - 1) * 90 + to]
        }
        key ^= Self.zPiece[me][Int(myType - 1) * 90 + from]
        key ^= Self.zPiece[me][Int(myType - 1) * 90 + to]

        board[to] = moving
        board[from] = 0

        if myType == 1 {
            if me == 0 { kingSq.0 = to } else { kingSq.1 = to }
        }

        halfmoveClock = captured != 0 ? 0 : halfmoveClock &+ 1
        currentPlayer = 1 - currentPlayer
        ply += 1
        zobristKey = key
        history.append(key)
        posCounts[key, default: 0] += 1
    }

    // MARK: - 终局

    public var isOver: Bool {
        if halfmoveClock >= 120 { return true }              // 120 半回合无吃子判和
        if (posCounts[zobristKey] ?? 0) >= 3 { return true } // 三次重复局面判和
        return legalMoves().isEmpty                          // 无合法着法即负（象棋无逼和）
    }

    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        if legalMoves().isEmpty {
            // 被将死或困毙：无着法一方负
            return currentPlayer == player ? 0.0 : 1.0
        }
        return 0.5                                           // 无吃子判和 / 三次重复
    }

    // MARK: - 评估

    /// 車前方（通向对方底线）同列无己方兵卒 → 开放线
    private func openFile(r: Int, col: Int, player: Int) -> Bool {
        let dir = player == 0 ? -1 : 1
        var nr = r + dir
        while nr >= 0 && nr < 10 {
            let p = board[nr * 9 + col]
            if p != 0, Xiangqi.typeOf(p) == 7, Xiangqi.colorOf(p) == player { return false }
            nr += dir
        }
        return true
    }

    public func evaluate() -> Double {
        var scores = [0.0, 0.0]
        for (sq, p) in board.enumerated() where p != 0 {
            let t = Int(Xiangqi.typeOf(p))
            let side = Xiangqi.colorOf(p)
            var v = Xiangqi.pieceValues[t]
            let (r, col) = Xiangqi.rc(sq)
            switch t {
            case 7:
                // 兵：过河 1.8，深入与居中略加分
                let crossed = side == 0 ? r <= 4 : r >= 5
                if crossed {
                    v = 1.8
                    let advance = side == 0 ? (4 - r) : (r - 5)
                    v += Double(advance) * 0.08
                    v += (4.0 - abs(4.0 - Double(col))) * 0.03
                }
            case 4:
                // 馬：居中加分
                v += (4.0 - abs(4.0 - Double(col))) * 0.05
                v += (4.5 - abs(4.5 - Double(r))) * 0.03
            case 6:
                // 炮：居中略加分
                v += (4.0 - abs(4.0 - Double(col))) * 0.03
            case 5:
                // 車：开放线粗略加分
                if openFile(r: r, col: col, player: side) { v += 0.25 }
            default:
                break
            }
            scores[side] += v
        }
        let diff = scores[0] - scores[1]
        return (currentPlayer == 0 ? diff : -diff) + 0.05
    }

    // MARK: - 搜索钩子

    /// MVV-LVA：victim*10 - attacker（帥不可被吃，victim 不会是帥）
    public func orderHint(for move: XiangqiMove) -> Int {
        let victim = board[Int(move.to)]
        guard victim != 0 else { return 0 }
        let attacker = board[Int(move.from)]
        let v = Xiangqi.pieceValues[Int(Xiangqi.typeOf(victim))]
        let a = Xiangqi.pieceValues[Int(Xiangqi.typeOf(attacker))]
        return Int(v * 10 - a)
    }

    public func isTactical(_ move: XiangqiMove) -> Bool {
        board[Int(move.to)] != 0
    }
}

/// 中国象棋 AI（通用 α-β 搜索）
public enum XiangqiAI {
    public static func bestMove(in game: Xiangqi, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<Xiangqi.XiangqiMove> {
        let profile = DifficultyProfile.for(difficulty, depthScale: 1.0)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

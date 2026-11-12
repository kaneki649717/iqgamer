import Foundation

/// 国际象棋。
/// 棋盘 8×8，index = row*8+col；row 0 = 黑方底线（第 8 横排），row 7 = 白方底线。
/// 玩家 0 = 白（先手，row 向减小前进），1 = 黑。
/// 棋子编码：0 空；1-6 = 白 兵马车象后王；| 0b1000 = 黑。
public struct Chess: BoardGame {
    public struct ChessMove: Hashable, Sendable, Comparable {
        public let from: UInt8
        public let to: UInt8
        public let promotion: UInt8? // nil=无；0=后 1=车 2=象 3=马
        public init(from: UInt8, to: UInt8, promotion: UInt8? = nil) {
            self.from = from
            self.to = to
            self.promotion = promotion
        }
        public static func < (a: ChessMove, b: ChessMove) -> Bool {
            if a.from != b.from { return a.from < b.from }
            if a.to != b.to { return a.to < b.to }
            return (a.promotion ?? 255) < (b.promotion ?? 255)
        }
    }

    // MARK: - 状态

    public private(set) var board: [UInt8]          // 64 格
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    public private(set) var castling: UInt8         // 1=白王侧 2=白后侧 4=黑王侧 8=黑后侧
    public private(set) var epSquare: UInt8         // 255 = 无（吃过路兵目标格）
    public private(set) var halfmoveClock: UInt16   // 50 回合规则计数
    public private(set) var zobristKey: UInt64
    var history: [UInt64]                           // 局面 key 历史（含初始）
    var posCounts: [UInt64: Int]                    // 三次重复计数
    var kingSq: (Int, Int)                          // (白王格, 黑王格)

    // Zobrist 键表
    static let zPiece: [[UInt64]] = [
        Zobrist.table(6 * 64, seed: 0xC0FFEE01),
        Zobrist.table(6 * 64, seed: 0xC0FFEE02),
    ]
    static let zCastle = Zobrist.table(16, seed: 0xC0FFEE03)
    static let zEP = Zobrist.table(8, seed: 0xC0FFEE04)
    static let zSide = Zobrist.table(2, seed: 0xC0FFEE05)[1]

    static let pieceValues: [Double] = [0, 1.0, 3.2, 3.3, 5.0, 9.0, 0] // 按类型 0..6

    public init() {
        board = Array(repeating: 0, count: 64)
        let back = [4, 2, 3, 5, 6, 3, 2, 4] // 车马象后王象马车
        for c in 0..<8 {
            board[c] = UInt8(0b1000 | back[c])          // 黑（row 0）
            board[8 + c] = UInt8(0b1000 | 1)            // 黑兵
            board[48 + c] = 1                            // 白兵
            board[56 + c] = UInt8(back[c])               // 白
        }
        currentPlayer = 0
        ply = 0
        castling = 0b1111
        epSquare = 255
        halfmoveClock = 0
        kingSq = (60, 4)
        let k = Chess.computeKey(board: board, castling: castling, ep: epSquare, player: currentPlayer)
        zobristKey = k
        history = [k]
        posCounts = [k: 1]
    }

    /// 测试工厂：直接摆子
    init(board: [UInt8], player: Int, castling: UInt8 = 0, ep: UInt8 = 255, halfmove: UInt16 = 0) {
        self.board = board
        self.currentPlayer = player
        self.castling = castling
        self.epSquare = ep
        self.halfmoveClock = halfmove
        self.ply = 0
        var wk = 60, bk = 4
        for (i, p) in board.enumerated() where Chess.typeOf(p) == 6 {
            if Chess.colorOf(p) == 0 { wk = i } else { bk = i }
        }
        self.kingSq = (wk, bk)
        let k = Chess.computeKey(board: board, castling: castling, ep: ep, player: player)
        self.zobristKey = k
        self.history = [k]
        self.posCounts = [k: 1]
    }

    public func copy() -> Self { self }

    // MARK: - 棋子工具

    @inline(__always) public static func typeOf(_ p: UInt8) -> UInt8 { p & 0b111 }
    @inline(__always) public static func colorOf(_ p: UInt8) -> Int { (p & 0b1000) != 0 ? 1 : 0 }
    @inline(__always) static func isWhite(_ p: UInt8) -> Bool { p != 0 && (p & 0b1000) == 0 }
    @inline(__always) static func isBlack(_ p: UInt8) -> Bool { p & 0b1000 != 0 && p & 0b111 != 0 }
    static func rc(_ sq: Int) -> (Int, Int) { (sq >> 3, sq & 7) }

    // MARK: - Zobrist

    static func computeKey(board: [UInt8], castling: UInt8, ep: UInt8, player: Int) -> UInt64 {
        var k: UInt64 = 0
        for (sq, p) in board.enumerated() where p != 0 {
            k ^= zPiece[colorOf(p)][Int(typeOf(p) - 1) * 64 + sq]
        }
        k ^= zCastle[Int(castling) & 15]
        if ep != 255 { k ^= zEP[Int(ep) & 7] }
        if player == 1 { k ^= zSide }
        return k
    }

    // MARK: - 攻击检测

    /// sq 是否被 player 一方攻击
    func attacked(_ sq: Int, by player: Int) -> Bool {
        let (r, c) = Chess.rc(sq)
        // 兵
        if player == 0 {
            if r < 7 {
                if c > 0 && board[sq + 7] == 1 { return true }
                if c < 7 && board[sq + 9] == 1 { return true }
            }
        } else {
            if r > 0 {
                if c > 0 && board[sq - 9] == 0b1001 { return true }
                if c < 7 && board[sq - 7] == 0b1001 { return true }
            }
        }
        // 马
        let kn = player == 0 ? UInt8(2) : UInt8(0b1010)
        for (dr, dc) in Self.knightOffsets {
            let nr = r + dr, nc = c + dc
            if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr * 8 + nc] == kn { return true }
        }
        // 王
        let kg = player == 0 ? UInt8(6) : UInt8(0b1110)
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let nr = r + dr, nc = c + dc
                if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr * 8 + nc] == kg { return true }
            }
        }
        // 滑子
        for (i, (dr, dc)) in Self.slideDirs.enumerated() {
            var nr = r + dr, nc = c + dc
            while nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                let p = board[nr * 8 + nc]
                if p != 0 {
                    let t = Chess.typeOf(p)
                    if Chess.colorOf(p) == player {
                        let diagonal = i >= 4
                        if t == 5 || t == 6 || (diagonal ? t == 3 : t == 4) { return true }
                    }
                    break
                }
                nr += dr; nc += dc
            }
        }
        return false
    }

    static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let slideDirs = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]

    var isInCheck: Bool {
        attacked(currentPlayer == 0 ? kingSq.0 : kingSq.1, by: 1 - currentPlayer)
    }

    // MARK: - 走法生成

    public func legalMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        appendPseudoMoves(to: &moves)
        var legal: [ChessMove] = []
        legal.reserveCapacity(moves.count)
        for m in moves {
            var c = self
            // play 的轻校验对生成走法必然通过
            c.forcePlay(m)
            let ks = c.currentPlayer == 1 ? c.kingSq.0 : c.kingSq.1 // 走完后翻转，走子方 = 1 - currentPlayer
            if !c.attacked(ks, by: c.currentPlayer) {
                legal.append(m)
            }
        }
        return legal
    }

    private func appendPseudoMoves(to moves: inout [ChessMove]) {
        let me = currentPlayer
        for sq in 0..<64 {
            let p = board[sq]
            guard p != 0, Chess.colorOf(p) == me else { continue }
            let (r, c) = Chess.rc(sq)
            let t = Chess.typeOf(p)
            switch t {
            case 1: appendPawnMoves(from: sq, r: r, c: c, player: me, to: &moves)
            case 2: appendOffsets(from: sq, r: r, c: c, player: me, offsets: Self.knightOffsets, slider: false, to: &moves)
            case 3: appendOffsets(from: sq, r: r, c: c, player: me, offsets: Array(Self.slideDirs[4...]), slider: true, to: &moves)
            case 4: appendOffsets(from: sq, r: r, c: c, player: me, offsets: Array(Self.slideDirs[0..<4]), slider: true, to: &moves)
            case 5: appendOffsets(from: sq, r: r, c: c, player: me, offsets: Self.slideDirs, slider: true, to: &moves)
            case 6: appendKingMoves(from: sq, r: r, c: c, player: me, to: &moves)
            default: break
            }
        }
        appendCastling(to: &moves)
    }

    private func appendPawnMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [ChessMove]) {
        let dir = player == 0 ? -1 : 1
        let startRow = player == 0 ? 6 : 1
        let promoRow = player == 0 ? 0 : 7
        let forward = sq + dir * 8
        // 前进
        if forward >= 0 && forward < 64 && board[forward] == 0 {
            if r + dir == promoRow {
                for p in UInt8(0)...UInt8(3) { moves.append(ChessMove(from: UInt8(sq), to: UInt8(forward), promotion: p)) }
            } else {
                moves.append(ChessMove(from: UInt8(sq), to: UInt8(forward)))
                if r == startRow {
                    let dbl = sq + dir * 16
                    if board[dbl] == 0 { moves.append(ChessMove(from: UInt8(sq), to: UInt8(dbl))) }
                }
            }
        }
        // 吃子（含过路兵）
        for dc in [-1, 1] {
            let nc = c + dc
            if nc < 0 || nc > 7 { continue }
            let target = sq + dir * 8 + dc
            if target < 0 || target >= 64 { continue }
            let tp = board[target]
            if tp != 0 && Chess.colorOf(tp) != player {
                if r + dir == promoRow {
                    for p in UInt8(0)...UInt8(3) { moves.append(ChessMove(from: UInt8(sq), to: UInt8(target), promotion: p)) }
                } else {
                    moves.append(ChessMove(from: UInt8(sq), to: UInt8(target)))
                }
            } else if tp == 0 && Int(epSquare) == target {
                moves.append(ChessMove(from: UInt8(sq), to: UInt8(target)))
            }
        }
    }

    private func appendOffsets(from sq: Int, r: Int, c: Int, player: Int, offsets: [(Int, Int)], slider: Bool, to moves: inout [ChessMove]) {
        for (dr, dc) in offsets {
            var nr = r + dr, nc = c + dc
            while nr >= 0 && nr < 8 && nc >= 0 && nc < 8 {
                let target = nr * 8 + nc
                let tp = board[target]
                if tp == 0 {
                    moves.append(ChessMove(from: UInt8(sq), to: UInt8(target)))
                } else {
                    if Chess.colorOf(tp) != player {
                        moves.append(ChessMove(from: UInt8(sq), to: UInt8(target)))
                    }
                    break
                }
                if !slider { break }
                nr += dr; nc += dc
            }
        }
    }

    private func appendKingMoves(from sq: Int, r: Int, c: Int, player: Int, to moves: inout [ChessMove]) {
        appendOffsets(from: sq, r: r, c: c, player: player, offsets: Self.slideDirs, slider: false, to: &moves)
    }

    private func appendCastling(to moves: inout [ChessMove]) {
        let opp = 1 - currentPlayer
        if currentPlayer == 0 {
            // 白：王 e1(60)
            if castling & 1 != 0, board[61] == 0, board[62] == 0,
               !attacked(60, by: opp), !attacked(61, by: opp) {
                moves.append(ChessMove(from: 60, to: 62))
            }
            if castling & 2 != 0, board[57] == 0, board[58] == 0, board[59] == 0,
               !attacked(60, by: opp), !attacked(59, by: opp) {
                moves.append(ChessMove(from: 60, to: 58))
            }
        } else {
            // 黑：王 e8(4)
            if castling & 4 != 0, board[5] == 0, board[6] == 0,
               !attacked(4, by: opp), !attacked(5, by: opp) {
                moves.append(ChessMove(from: 4, to: 6))
            }
            if castling & 8 != 0, board[1] == 0, board[2] == 0, board[3] == 0,
               !attacked(4, by: opp), !attacked(3, by: opp) {
                moves.append(ChessMove(from: 4, to: 2))
            }
        }
    }

    // MARK: - 走子

    public mutating func play(_ move: ChessMove) throws {
        let from = Int(move.from), to = Int(move.to)
        guard from >= 0 && from < 64 && to >= 0 && to < 64 else { throw MoveError.illegalMove }
        let p = board[from]
        guard p != 0, Chess.colorOf(p) == currentPlayer else { throw MoveError.illegalMove }
        if let promo = move.promotion, promo > 3 { throw MoveError.illegalMove }
        let tp = board[to]
        guard tp == 0 || Chess.colorOf(tp) != currentPlayer else { throw MoveError.illegalMove }
        // 王被吃属于非法（不应出现）
        guard Chess.typeOf(tp) != 6 else { throw MoveError.illegalMove }
        forcePlay(move)
    }

    /// 内部快速走子（已保证伪合法）
    private mutating func forcePlay(_ move: ChessMove) {
        let from = Int(move.from), to = Int(move.to)
        let moving = board[from]
        let myType = Chess.typeOf(moving)
        let me = currentPlayer
        var key = zobristKey
        key ^= Self.zSide
        if epSquare != 255 { key ^= Self.zEP[Int(epSquare) & 7] }

        var newEP: UInt8 = 255
        var newRights = castling
        var newHalf = halfmoveClock &+ 1

        // 吃子
        var capturedSq = -1
        var capturedPiece: UInt8 = 0
        if board[to] != 0 {
            capturedSq = to
            capturedPiece = board[to]
        } else if myType == 1, epSquare != 255, to == Int(epSquare) {
            capturedSq = to + (me == 0 ? 8 : -8)
            capturedPiece = board[capturedSq]
        }
        if capturedPiece != 0 {
            key ^= Self.zPiece[Chess.colorOf(capturedPiece)][Int(Chess.typeOf(capturedPiece) - 1) * 64 + capturedSq]
            newHalf = 0
        }

        // 移动子
        key ^= Self.zPiece[me][Int(myType - 1) * 64 + from]
        let placedType: UInt8
        if let promo = move.promotion {
            placedType = [5, 4, 3, 2][Int(promo)]
        } else {
            placedType = myType
        }
        key ^= Self.zPiece[me][Int(placedType - 1) * 64 + to]

        var newBoard = board
        newBoard[from] = 0
        if capturedSq >= 0 && capturedSq != to { newBoard[capturedSq] = 0 }
        newBoard[to] = me == 0 ? placedType : (0b1000 | placedType)

        // 易位：王横移两格 → 同时动车
        if myType == 6, abs(to - from) == 2 {
            let rookFrom: Int, rookTo: Int
            if to > from { rookFrom = me == 0 ? 63 : 7; rookTo = me == 0 ? 61 : 5 }
            else { rookFrom = me == 0 ? 56 : 0; rookTo = me == 0 ? 59 : 3 }
            let rook = newBoard[rookFrom]
            newBoard[rookFrom] = 0
            newBoard[rookTo] = rook
            key ^= Self.zPiece[me][Int(Chess.typeOf(rook) - 1) * 64 + rookFrom]
            key ^= Self.zPiece[me][Int(Chess.typeOf(rook) - 1) * 64 + rookTo]
        }

        // 权利更新
        if myType == 6 {
            newRights &= me == 0 ? ~0b0011 : ~0b1100
        }
        for sq in [from, to] {
            switch sq {
            case 63: newRights &= ~0b0001
            case 56: newRights &= ~0b0010
            case 7: newRights &= ~0b0100
            case 0: newRights &= ~0b1000
            default: break
            }
        }
        if newRights != castling {
            key ^= Self.zCastle[Int(castling) & 15]
            key ^= Self.zCastle[Int(newRights) & 15]
        }

        // 过路兵目标
        if myType == 1, abs(to - from) == 16 {
            newEP = UInt8((from + to) / 2)
            key ^= Self.zEP[Int(newEP) & 7]
        }

        // 王位置
        var newKingSq = kingSq
        if myType == 6 {
            if me == 0 { newKingSq.0 = to } else { newKingSq.1 = to }
        }

        if myType == 1 { newHalf = 0 }

        board = newBoard
        castling = newRights
        epSquare = newEP
        halfmoveClock = newHalf
        kingSq = newKingSq
        currentPlayer = 1 - currentPlayer
        ply += 1
        zobristKey = key
        history.append(key)
        posCounts[key, default: 0] += 1
    }

    // MARK: - 终局

    public var isOver: Bool {
        if halfmoveClock >= 100 { return true }
        if (posCounts[zobristKey] ?? 0) >= 3 { return true }
        if insufficientMaterial { return true }
        return legalMoves().isEmpty
    }

    var insufficientMaterial: Bool {
        var minors = 0
        var bishopSquares: [Int] = []
        for (sq, p) in board.enumerated() where p != 0 {
            switch Chess.typeOf(p) {
            case 1, 4, 5: return false // 兵车后 → 必有子力
            case 2, 3:
                minors += 1
                if Chess.typeOf(p) == 3 { bishopSquares.append(((sq >> 3) + sq) & 1) }
            default: break
            }
            if minors > 2 { return false }
        }
        // K-K、单轻子-K、双象同色-K 等
        if minors <= 1 { return true }
        if minors == bishopSquares.count, Set(bishopSquares).count == 1 { return true }
        return false
    }

    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        // 被将死：行棋方无着且被将
        if legalMoves().isEmpty {
            if isInCheck {
                return currentPlayer == player ? 0.0 : 1.0
            }
            return 0.5 // 逼和
        }
        return 0.5 // 50 回合 / 重复 / 子力不足
    }

    // MARK: - 评估

    static let pstPawn: [Double] = [
         0,  0,  0,  0,  0,  0,  0,  0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
         5,  5, 10, 25, 25, 10,  5,  5,
         0,  0,  0, 20, 20,  0,  0,  0,
         5, -5, -10,  0,  0, -10, -5,  5,
         5, 10, 10, -20, -20, 10, 10,  5,
         0,  0,  0,  0,  0,  0,  0,  0,
    ]
    static let pstKnight: [Double] = [
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20,   0,   0,   0,   0, -20, -40,
        -30,   0,  10,  15,  15,  10,   0, -30,
        -30,   5,  15,  20,  20,  15,   5, -30,
        -30,   0,  15,  20,  20,  15,   0, -30,
        -30,   5,  10,  15,  15,  10,   5, -30,
        -40, -20,   0,   5,   5,   0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    ]
    static let pstBishop: [Double] = [
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10,   0,   0,   0,   0,   0,   0, -10,
        -10,   0,   5,  10,  10,   5,   0, -10,
        -10,   5,   5,  10,  10,   5,   5, -10,
        -10,   0,  10,  10,  10,  10,   0, -10,
        -10,  10,  10,  10,  10,  10,  10, -10,
        -10,   5,   0,   0,   0,   0,   5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    ]
    static let pstRook: [Double] = [
          0,   0,   0,   0,   0,   0,   0,   0,
          5,  10,  10,  10,  10,  10,  10,   5,
         -5,   0,   0,   0,   0,   0,   0,  -5,
         -5,   0,   0,   0,   0,   0,   0,  -5,
         -5,   0,   0,   0,   0,   0,   0,  -5,
         -5,   0,   0,   0,   0,   0,   0,  -5,
         -5,   0,   0,   0,   0,   0,   0,  -5,
          0,   0,   0,   5,   5,   0,   0,   0,
    ]
    static let pstQueen: [Double] = [
        -20, -10, -10,  -5,  -5, -10, -10, -20,
        -10,   0,   0,   0,   0,   0,   0, -10,
        -10,   0,   5,   5,   5,   5,   0, -10,
         -5,   0,   5,   5,   5,   5,   0,  -5,
          0,   0,   5,   5,   5,   5,   0,  -5,
        -10,   5,   5,   5,   5,   5,   0, -10,
        -10,   0,   5,   0,   0,   0,   0, -10,
        -20, -10, -10,  -5,  -5, -10, -10, -20,
    ]
    static let pstKingMid: [Double] = [
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
         20,  20,   0,   0,   0,   0,  20,  20,
         20,  30,  10,   0,   0,  10,  30,  20,
    ]
    static let pstKingEnd: [Double] = [
        -50, -40, -30, -20, -20, -30, -40, -50,
        -30, -20, -10,   0,   0, -10, -20, -30,
        -30, -10,  20,  30,  30,  20, -10, -30,
        -30, -10,  30,  40,  40,  30, -10, -30,
        -30, -10,  30,  40,  40,  30, -10, -30,
        -30, -10,  20,  30,  30,  20, -10, -30,
        -30, -30,   0,   0,   0,   0, -30, -30,
        -50, -30, -30, -30, -30, -30, -30, -50,
    ]

    public func evaluate() -> Double {
        var w = 0.0, b = 0.0
        var wB = 0, bB = 0
        var wNonPawn = 0.0, bNonPawn = 0.0
        for (sq, p) in board.enumerated() where p != 0 {
            let t = Int(Chess.typeOf(p))
            let c = Chess.colorOf(p)
            let idx = c == 0 ? sq : (sq ^ 56)
            var v = Chess.pieceValues[t]
            switch t {
            case 1: v += Chess.pstPawn[idx] / 100
            case 2: v += Chess.pstKnight[idx] / 100
            case 3: v += Chess.pstBishop[idx] / 100
            case 4: v += Chess.pstRook[idx] / 100
            case 5: v += Chess.pstQueen[idx] / 100
            default: break
            }
            if t == 3 { if c == 0 { wB += 1 } else { bB += 1 } }
            if t != 1 && t != 6 {
                if c == 0 { wNonPawn += Chess.pieceValues[t] } else { bNonPawn += Chess.pieceValues[t] }
            }
            if c == 0 { w += v } else { b += v }
        }
        if wB >= 2 { w += 0.35 }
        if bB >= 2 { b += 0.35 }
        // 王位置：中局靠边/残局居中
        let endgame = (wNonPawn + bNonPawn) < 12
        if endgame {
            w += Chess.pstKingEnd[kingSq.0 ^ 56] / 100
            b += Chess.pstKingEnd[kingSq.1] / 100
        } else {
            w += Chess.pstKingMid[kingSq.0 ^ 56] / 100
            b += Chess.pstKingMid[kingSq.1] / 100
        }
        let diff = w - b
        return (currentPlayer == 0 ? diff : -diff) + 0.08
    }

    // MARK: - 搜索钩子

    public func orderHint(for move: ChessMove) -> Int {
        let victim = Chess.typeOf(board[Int(move.to)])
        let attacker = Chess.typeOf(board[Int(move.from)])
        var h = Int((Chess.pieceValues[Int(victim)] * 10 - Chess.pieceValues[Int(attacker)] * 1) * 10)
        if move.promotion != nil { h += 900 }
        return h
    }

    public func isTactical(_ move: ChessMove) -> Bool {
        board[Int(move.to)] != 0 || move.promotion != nil ||
        (Chess.typeOf(board[Int(move.from)]) == 1 && epSquare != 255 && Int(move.to) == Int(epSquare))
    }
}

/// 国际象棋 AI
public enum ChessAI {
    public static func bestMove(in game: Chess, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<Chess.ChessMove> {
        let profile = DifficultyProfile.for(difficulty, depthScale: 1.0)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

import Foundation

/// 国际跳棋（10×10，FMJD 规则）。
///
/// - 棋盘 10×10，index = row*10+col（全格编码）；深色格 = (row+col)%2==1，浅色格恒空。
/// - 玩家 0 = 白（先手），初始占 row 0-3 的深色格，向 row 增大方向前进（离开自家底线），
///   row 9 为升王线；玩家 1 = 黑，初始占 row 6-9，向 row 减小方向前进，row 0 为升王线。
///   （规格中两处方向注释与初始摆位自相矛盾——若按字面「白向 row 减小」走，
///   开局白棋前方全被己方占住、零合法着法；故以初始摆位为准，双方朝对方底线前进。）
/// - 兵：斜前 1 格平移；吃子斜前/斜后均可（相邻敌子，身后须有空格）。
/// - 王（飞王）：沿对角线任意距离平移/吃子；吃子时越过敌子后可落在其后任意空格，
///   但不得越过第二个子。
/// - 有吃必吃，且必须选吃子数最多的一条链（majority rule）；连吃不可重复跳同一枚
///   敌子；被跳敌子整条链结束后才移除（Turkish strike：链中仍占原格，阻挡落点与航线）。
/// - 兵吃子中途到达底线：在该格停下并立即升王；若还能继续吃则必须以王继续（FMJD）。
/// - 终局：一方无子或无合法着法判负；连续 50 个半回合无吃子且无兵动判和（0.5）。
public struct Draughts: BoardGame {

    // MARK: - 着法

    /// 着法：起点 + 每次落点（≥2 元素）。平移 = 2 元素；n 段连吃 = n+1 元素。
    public struct DraughtsMove: Hashable, Sendable, Comparable {
        public let path: [UInt8]

        public init(path: [UInt8]) {
            self.path = path
        }

        /// 逐元素字典序比较
        public static func < (a: DraughtsMove, b: DraughtsMove) -> Bool {
            let n = min(a.path.count, b.path.count)
            for i in 0..<n where a.path[i] != b.path[i] {
                return a.path[i] < b.path[i]
            }
            return a.path.count < b.path.count
        }
    }

    /// 棋子编码（棋盘格取值）
    public enum Piece {
        public static let empty: UInt8 = 0
        public static let whiteMan: UInt8 = 1
        public static let whiteKing: UInt8 = 2
        public static let blackMan: UInt8 = 3
        public static let blackKing: UInt8 = 4
    }

    // MARK: - 状态

    /// 100 格棋盘；0 空，1 白兵，2 白王，3 黑兵，4 黑王；浅色格恒为 0
    public private(set) var squares: [UInt8]
    public private(set) var currentPlayer: Int
    public private(set) var ply: Int
    /// 连续「无吃子且无兵动」的半回合数，达到 50 判和
    public private(set) var idles: Int
    public private(set) var zobristKey: UInt64

    /// Zobrist 键表：pieceType ∈ 1...4，索引 (piece-1)*100+sq
    static let zp = Zobrist.table(400, seed: 0xB00C_0000_0001)
    static let zTurn = Zobrist.table(2, seed: 0xB00C_0000_0002)[1]

    public init() {
        var s = [UInt8](repeating: Piece.empty, count: 100)
        for r in 0...3 {
            for c in 0..<10 where (r + c) % 2 == 1 { s[r * 10 + c] = Piece.whiteMan }
        }
        for r in 6...9 {
            for c in 0..<10 where (r + c) % 2 == 1 { s[r * 10 + c] = Piece.blackMan }
        }
        self.init(squares: s)
    }

    /// 内部测试工厂：直接摆盘（squares 须为 100 格，且仅深色格允许有子）
    init(squares: [UInt8], currentPlayer: Int = 0, idles: Int = 0, ply: Int = 0) {
        precondition(squares.count == 100, "棋盘须为 100 格")
        for i in 0..<100 where squares[i] != 0 {
            precondition((i / 10 + i % 10) % 2 == 1, "浅色格不允许有子：sq=\(i)")
        }
        self.squares = squares
        self.currentPlayer = currentPlayer
        self.idles = idles
        self.ply = ply
        var k: UInt64 = 0
        for i in 0..<100 where squares[i] != 0 {
            k ^= Self.zp[(Int(squares[i]) - 1) * 100 + i]
        }
        if currentPlayer == 1 { k ^= Self.zTurn }
        self.zobristKey = k
    }

    public func copy() -> Self { self }

    public var whiteCount: Int { squares.filter { Self.owner(of: $0) == 0 }.count }
    public var blackCount: Int { squares.filter { Self.owner(of: $0) == 1 }.count }

    // MARK: - 基础工具

    static func rc(_ sq: UInt8) -> (Int, Int) { (Int(sq) / 10, Int(sq) % 10) }
    static func owner(of piece: UInt8) -> Int { piece == 0 ? -1 : (piece <= Piece.whiteKing ? 0 : 1) }
    static func isKingPiece(_ piece: UInt8) -> Bool { piece == Piece.whiteKing || piece == Piece.blackKing }
    /// 升王线：白 row 9，黑 row 0
    static func promoRow(for player: Int) -> Int { player == 0 ? 9 : 0 }
    static let dirs: [(Int, Int)] = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    static func inBoard(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 10 && c >= 0 && c < 10 }

    // MARK: - 吃子链枚举

    /// 枚举从 sq 出发的全部「极大」吃子链（path：起点+每次落点）。
    /// 虚拟盘 b：提起行棋子，被跳子保留在盘上（Turkish strike）。
    func captureChains(from sq: UInt8) -> [[UInt8]] {
        let piece = squares[Int(sq)]
        guard piece != 0 else { return [] }
        let p = Self.owner(of: piece)
        var b = squares
        b[Int(sq)] = 0
        var results: [[UInt8]] = []
        var path: [UInt8] = [sq]
        var jumped: [UInt8] = []
        extend(Int(sq), isKing: Self.isKingPiece(piece), player: p,
               board: &b, jumped: &jumped, path: &path, into: &results)
        return results
    }

    /// 递归延长吃子链；无法继续吃且已吃过子时记为一条极大链。
    /// 每次递归消耗一枚未跳过的敌子（jumped 只增不减），故深度有限、必然终止。
    private func extend(_ pos: Int, isKing: Bool, player: Int,
                        board b: inout [UInt8], jumped: inout [UInt8],
                        path: inout [UInt8], into results: inout [[UInt8]]) {
        let r0 = pos / 10, c0 = pos % 10
        var extended = false
        for (dr, dc) in Self.dirs {
            if isKing {
                // 飞王：沿对角线滑过空格，首个遇到的子须为未跳过的敌子
                var r = r0 + dr, c = c0 + dc
                while Self.inBoard(r, c) && b[r * 10 + c] == 0 { r += dr; c += dc }
                guard Self.inBoard(r, c) else { continue }
                let esq = r * 10 + c
                guard Self.owner(of: b[esq]) == 1 - player, !jumped.contains(UInt8(esq)) else { continue }
                // 落点：敌子之后、下一个子（或边界）之前的连续空格；
                // 已跳过的子仍在盘上，自然终止落点区间（不得越过第二个子 / Turkish strike）
                var lr = r + dr, lc = c + dc
                while Self.inBoard(lr, lc) && b[lr * 10 + lc] == 0 {
                    extended = true
                    let dest = lr * 10 + lc
                    path.append(UInt8(dest))
                    jumped.append(UInt8(esq))
                    extend(dest, isKing: true, player: player,
                           board: &b, jumped: &jumped, path: &path, into: &results)
                    path.removeLast()
                    jumped.removeLast()
                    lr += dr
                    lc += dc
                }
            } else {
                // 兵：斜前/斜后相邻敌子，身后须为空格
                let r1 = r0 + dr, c1 = c0 + dc
                guard Self.inBoard(r1, c1) else { continue }
                let mid = r1 * 10 + c1
                guard Self.owner(of: b[mid]) == 1 - player, !jumped.contains(UInt8(mid)) else { continue }
                let r2 = r0 + 2 * dr, c2 = c0 + 2 * dc
                guard Self.inBoard(r2, c2), b[r2 * 10 + c2] == 0 else { continue }
                extended = true
                let dest = r2 * 10 + c2
                path.append(UInt8(dest))
                jumped.append(UInt8(mid))
                if dest / 10 == Self.promoRow(for: player) {
                    // 底线停下立即升王；若还能吃则以王继续（FMJD）
                    extend(dest, isKing: true, player: player,
                           board: &b, jumped: &jumped, path: &path, into: &results)
                } else {
                    extend(dest, isKing: false, player: player,
                           board: &b, jumped: &jumped, path: &path, into: &results)
                }
                path.removeLast()
                jumped.removeLast()
            }
        }
        if !extended && !jumped.isEmpty {
            results.append(path)
        }
    }

    // MARK: - 合法着法

    /// 平移着法（仅在无任何吃子时生成）
    func quietMoves(for player: Int) -> [DraughtsMove] {
        var moves: [DraughtsMove] = []
        for sq in 0..<100 where Self.owner(of: squares[sq]) == player {
            let (r, c) = Self.rc(UInt8(sq))
            if Self.isKingPiece(squares[sq]) {
                for (dr, dc) in Self.dirs {
                    var r2 = r + dr, c2 = c + dc
                    while Self.inBoard(r2, c2) && squares[r2 * 10 + c2] == 0 {
                        moves.append(DraughtsMove(path: [UInt8(sq), UInt8(r2 * 10 + c2)]))
                        r2 += dr
                        c2 += dc
                    }
                }
            } else {
                let dr = player == 0 ? 1 : -1
                for dc in [-1, 1] {
                    let r2 = r + dr, c2 = c + dc
                    if Self.inBoard(r2, c2) && squares[r2 * 10 + c2] == 0 {
                        moves.append(DraughtsMove(path: [UInt8(sq), UInt8(r2 * 10 + c2)]))
                    }
                }
            }
        }
        return moves
    }

    public func legalMoves() -> [DraughtsMove] {
        // 1) 吃子链：有吃必吃 + majority rule（只保留吃子数最多的极大链）
        var best: [[UInt8]] = []
        var bestCount = 0
        for sq in 0..<100 where Self.owner(of: squares[sq]) == currentPlayer {
            for chain in captureChains(from: UInt8(sq)) {
                let n = chain.count - 1
                if n > bestCount {
                    bestCount = n
                    best = [chain]
                } else if n == bestCount {
                    best.append(chain)
                }
            }
        }
        if bestCount > 0 {
            return best.map { DraughtsMove(path: $0) }
        }
        // 2) 无吃子 → 平移
        return quietMoves(for: currentPlayer)
    }

    /// 首跳存在性（用于终局快速判断；首跳落点不可能是起点，故无需提起行棋子）
    private func firstJumpExists(from sq: Int, player: Int) -> Bool {
        let king = Self.isKingPiece(squares[sq])
        let r0 = sq / 10, c0 = sq % 10
        for (dr, dc) in Self.dirs {
            if king {
                var r = r0 + dr, c = c0 + dc
                while Self.inBoard(r, c) && squares[r * 10 + c] == 0 { r += dr; c += dc }
                guard Self.inBoard(r, c) else { continue }
                if Self.owner(of: squares[r * 10 + c]) == 1 - player {
                    let lr = r + dr, lc = c + dc
                    if Self.inBoard(lr, lc) && squares[lr * 10 + lc] == 0 { return true }
                }
            } else {
                let r1 = r0 + dr, c1 = c0 + dc
                guard Self.inBoard(r1, c1) else { continue }
                if Self.owner(of: squares[r1 * 10 + c1]) == 1 - player {
                    let r2 = r0 + 2 * dr, c2 = c0 + 2 * dc
                    if Self.inBoard(r2, c2) && squares[r2 * 10 + c2] == 0 { return true }
                }
            }
        }
        return false
    }

    func hasQuietMove(_ player: Int) -> Bool {
        for sq in 0..<100 where Self.owner(of: squares[sq]) == player {
            let (r, c) = Self.rc(UInt8(sq))
            if Self.isKingPiece(squares[sq]) {
                for (dr, dc) in Self.dirs {
                    let r2 = r + dr, c2 = c + dc
                    if Self.inBoard(r2, c2) && squares[r2 * 10 + c2] == 0 { return true }
                }
            } else {
                let dr = player == 0 ? 1 : -1
                for dc in [-1, 1] {
                    let r2 = r + dr, c2 = c + dc
                    if Self.inBoard(r2, c2) && squares[r2 * 10 + c2] == 0 { return true }
                }
            }
        }
        return false
    }

    func hasAnyMove(_ player: Int) -> Bool {
        var hasPiece = false
        for sq in 0..<100 where Self.owner(of: squares[sq]) == player {
            hasPiece = true
            if firstJumpExists(from: sq, player: player) { return true }
        }
        guard hasPiece else { return false }
        return hasQuietMove(player)
    }

    // MARK: - 终局

    public var isOver: Bool {
        if idles >= 50 { return true }
        return !hasAnyMove(currentPlayer)
    }

    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        if idles >= 50 { return 0.5 }
        // 无子或无合法着法的一方（当前行棋方）判负
        return player == currentPlayer ? 0.0 : 1.0
    }

    // MARK: - 走子

    public mutating func play(_ move: DraughtsMove) throws {
        if isOver { throw MoveError.gameIsOver }
        guard move.path.count >= 2, legalMoves().contains(move) else {
            throw MoveError.illegalMove
        }
        apply(move)
    }

    /// 应用已验证合法的着法。
    /// 已验证的吃子链不会再次经过已跳子所在格，故按段顺序移除被跳子
    /// 与「整链结束后移除」（Turkish strike）语义等价。
    private mutating func apply(_ move: DraughtsMove) {
        let path = move.path
        let from = Int(path[0])
        let piece = squares[from]
        let wasMan = !Self.isKingPiece(piece)
        squares[from] = Piece.empty
        zobristKey ^= Self.zp[(Int(piece) - 1) * 100 + from]

        var captured = false
        for i in 0..<(path.count - 1) {
            let a = Int(path[i]), b = Int(path[i + 1])
            let (ra, ca) = (a / 10, a % 10)
            let (rb, cb) = (b / 10, b % 10)
            let dr = rb > ra ? 1 : (rb < ra ? -1 : 0)
            let dc = cb > ca ? 1 : (cb < ca ? -1 : 0)
            var r = ra + dr, c = ca + dc
            while r != rb || c != cb {
                let s = r * 10 + c
                let cp = squares[s]
                if cp != 0 {
                    squares[s] = Piece.empty
                    zobristKey ^= Self.zp[(Int(cp) - 1) * 100 + s]
                    captured = true
                }
                r += dr
                c += dc
            }
        }

        // 升王：兵的任一次落点到达底线即升王（含吃子中途升王后继续吃的情形）
        let last = Int(path.last!)
        var finalPiece = piece
        if wasMan, path.dropFirst().contains(where: { Int($0) / 10 == Self.promoRow(for: currentPlayer) }) {
            finalPiece = currentPlayer == 0 ? Piece.whiteKing : Piece.blackKing
        }
        squares[last] = finalPiece
        zobristKey ^= Self.zp[(Int(finalPiece) - 1) * 100 + last]

        // 吃子或动兵 → 计数清零；王平移 → 累计（50 半回合判和）
        if captured || wasMan {
            idles = 0
        } else {
            idles += 1
        }
        zobristKey ^= Self.zTurn
        currentPlayer = 1 - currentPlayer
        ply += 1
    }

    // MARK: - 搜索辅助

    /// 着法是否吃子（两段着法需查盘区分平移/单跳吃）
    public func isCapture(_ move: DraughtsMove) -> Bool {
        let path = move.path
        guard path.count >= 2 else { return false }
        if path.count > 2 { return true }
        let from = Int(path[0])
        let piece = squares[from]
        guard piece != 0, Self.owner(of: piece) == currentPlayer else { return false }
        let (ra, ca) = (from / 10, from % 10)
        let to = Int(path[1])
        let (rb, cb) = (to / 10, to % 10)
        let dr = rb - ra, dc = cb - ca
        guard dr != 0, abs(dr) == abs(dc) else { return false }
        if !Self.isKingPiece(piece) {
            guard abs(dr) == 2 else { return false }
            let mr = (ra + rb) / 2, mc = (ca + cb) / 2
            return Self.owner(of: squares[mr * 10 + mc]) == 1 - currentPlayer
        }
        // 王：沿线恰好一枚敌子
        let step = dr > 0 ? 1 : -1
        let stepC = dc > 0 ? 1 : -1
        var jumpedSq = -1
        var r = ra + step, c = ca + stepC
        while r != rb {
            if squares[r * 10 + c] != 0 {
                if jumpedSq != -1 { return false } // 越过两枚子，非合法单跳
                jumpedSq = r * 10 + c
            }
            r += step
            c += stepC
        }
        return jumpedSq != -1 && Self.owner(of: squares[jumpedSq]) == 1 - currentPlayer
    }

    public func orderHint(for move: DraughtsMove) -> Int {
        isCapture(move) ? (move.path.count - 1) * 100 : 0
    }

    /// 是否吃子（静态搜索扩展用）。注意：单跳吃 path 恰为 2 元素，
    /// 不能只按 path.count > 2 判断，需查盘。
    public func isTactical(_ move: DraughtsMove) -> Bool {
        isCapture(move)
    }

    /// 跳棋无将军概念
    public var isInCheck: Bool { false }

    // MARK: - 评估（当前行棋方视角，兵 = 1.0）

    public func evaluate() -> Double {
        var mine = 0.0
        var theirs = 0.0
        for sq in 0..<100 {
            let piece = squares[sq]
            guard piece != 0 else { continue }
            let ownerP = Self.owner(of: piece)
            let king = Self.isKingPiece(piece)
            let r = sq / 10, c = sq % 10
            var v = king ? 3.2 : 1.0
            if (3...6).contains(r) && (3...6).contains(c) { v += 0.05 }  // 中心
            if !king {
                if r == 0 || r == 9 || c == 0 || c == 9 { v += 0.1 }     // 边线兵护角
                if (ownerP == 0 ? r <= 1 : r >= 8) { v -= 0.05 }         // 落后兵
            }
            if ownerP == currentPlayer { mine += v } else { theirs += v }
        }
        return mine - theirs
    }
}

/// 国际跳棋 AI（通用 α-β 搜索）
public enum DraughtsAI {
    public static func bestMove(in game: Draughts, difficulty: AIDifficulty,
                                rng: SplitMix64? = nil) -> SearchResult<Draughts.DraughtsMove> {
        let profile = DifficultyProfile.for(difficulty, depthScale: 1.2)
        if let rng {
            return AlphaBetaSearch.bestMove(in: game, profile: profile, rng: rng)
        }
        return AlphaBetaSearch.bestMove(in: game, profile: profile)
    }
}

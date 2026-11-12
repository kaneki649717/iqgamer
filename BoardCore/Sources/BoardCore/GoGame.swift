import Foundation

// MARK: - flood fill 复用缓冲

/// flood fill 复用缓冲：用代际标记避免每步清空数组
struct GoScratch {
    var mark: [Int32]      // 棋子群访问标记
    var libMark: [Int32]   // 气点访问标记
    var gen: Int32 = 0
    var stack: [Int] = []

    init(boardSize: Int) {
        let n = boardSize * boardSize
        mark = Array(repeating: 0, count: n)
        libMark = Array(repeating: 0, count: n)
    }
}

// MARK: - 围棋

/// 围棋（中国规则数子法，贴目 7.5）。
/// 棋盘 9 / 13 / 19 路，index = row * boardSize + col。玩家 0 = 黑（先手），1 = 白。
/// 规则要点：
/// - 禁自杀（能提子则合法）；
/// - 简单劫：单子提单子、且落子后该子仅剩一口气时记 koPoint，下一手不得立即回提；
/// - 双方连续虚着终局；数子法计分（活子数 + 独占围空）；
/// - 死子启发：少于两个「真眼」（空点四邻全为己色，且该点八邻中己色 ≥ 5）的群判死，
///   从盘面移除并计入对方地域。
public struct GoGame: BoardGame {
    public typealias Move = GoMove

    // MARK: 着法

    public struct GoMove: Hashable, Sendable, Comparable {
        public let point: UInt16 // 0..<(boardSize*boardSize)，65535 = 虚着
        public static let pass = GoMove(point: 65535)

        public init(point: UInt16) { self.point = point }
        public init(_ p: Int) { self.point = UInt16(p) }

        public static func < (a: GoMove, b: GoMove) -> Bool { a.point < b.point }
    }

    // MARK: 状态

    /// 贴目（白 +7.5，中国规则数子）
    public static let komi = 7.5
    /// 支持的棋盘尺寸
    public static let supportedSizes: [Int] = [9, 13, 19]

    public let boardSize: Int
    public private(set) var board: [UInt8]         // 0 空 / 1 黑 / 2 白
    public private(set) var currentPlayer: Int     // 0 黑 1 白
    public private(set) var ply: Int               // 已走步数（含虚着）
    public private(set) var consecutivePasses: Int // 连续虚着数
    public private(set) var koPoint: Int           // 简单劫禁点，-1 = 无
    public private(set) var lastPoint: Int         // 上一手实着位置，-1 = 无
    public private(set) var zobristKey: UInt64

    static let zBlack = Zobrist.table(361, seed: 0x6F07_0000_0000_0001)
    static let zWhite = Zobrist.table(361, seed: 0x6F07_0000_0000_0002)
    static let zTurn = Zobrist.table(2, seed: 0x6F07_0000_0000_0003)[1]

    /// 默认 9 路盘（协议要求）
    public init() { self.init(boardSize: 9) }

    public init(boardSize: Int) {
        precondition(GoGame.supportedSizes.contains(boardSize), "围棋仅支持 9/13/19 路")
        self.boardSize = boardSize
        board = Array(repeating: 0, count: boardSize * boardSize)
        currentPlayer = 0
        ply = 0
        consecutivePasses = 0
        koPoint = -1
        lastPoint = -1
        zobristKey = 0
    }

    public func copy() -> Self { self }

    // MARK: 对局状态

    public var isOver: Bool { consecutivePasses >= 2 }

    /// 终局分：1.0 胜 / 0.0 负（贴 7.5 目下无和棋）；未终局返回 nil
    public func score(for player: Int) -> Double? {
        guard isOver else { return nil }
        let a = computeAreaScore()
        let blackWins = a.black > a.white + Self.komi
        return player == 0 ? (blackWins ? 1.0 : 0.0) : (blackWins ? 0.0 : 1.0)
    }

    /// 当前行棋方视角粗略形势差（仅供展示 / 调试，MCTS 不使用）：
    /// 数子分差（黑 - 白 - 贴目）按行棋进度做早中后期权重。
    public func evaluate() -> Double {
        let a = computeAreaScore()
        let blackLead = a.black - (a.white + Self.komi)
        let stones = board.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        let fill = Double(stones) / Double(boardSize * boardSize)
        let weight: Double = fill < 0.3 ? 0.25 : (fill < 0.65 ? 0.6 : 1.0)
        return (currentPlayer == 0 ? blackLead : -blackLead) * weight
    }

    /// 所有合法着法（合法空点 + 虚着）；终局后返回空数组
    public func legalMoves() -> [GoMove] {
        if isOver { return [] }
        var scratch = GoScratch(boardSize: boardSize)
        let color = UInt8(currentPlayer + 1)
        var moves: [GoMove] = []
        for p in 0..<(boardSize * boardSize) where board[p] == 0 {
            if GoGame.isLegalPoint(p, color: color, board: board, boardSize: boardSize,
                                   koPoint: koPoint, scratch: &scratch) {
                moves.append(GoMove(p))
            }
        }
        moves.append(.pass)
        return moves
    }

    // MARK: 落子

    public mutating func play(_ move: GoMove) throws {
        if isOver { throw MoveError.gameIsOver }
        var scratch = GoScratch(boardSize: boardSize)
        try playInternal(move, scratch: &scratch)
    }

    /// 内部落子（可复用 scratch；MCTS 扩展节点时使用）。非法时抛错且不改变任何状态。
    mutating func playInternal(_ move: GoMove, scratch: inout GoScratch) throws {
        if move == .pass {
            consecutivePasses += 1
            koPoint = -1
            lastPoint = -1
            togglePlayer()
            ply += 1
            return
        }
        let p = Int(move.point)
        guard p >= 0 && p < boardSize * boardSize && board[p] == 0 && p != koPoint else {
            throw MoveError.illegalMove
        }
        let color = UInt8(currentPlayer + 1)
        let r = GoGame.playInPlace(p, color: color, board: &board, boardSize: boardSize, scratch: &scratch)
        guard r.legal else { throw MoveError.illegalMove }
        let captured = r.captured

        // zobrist 增量维护：落子与提子都要 XOR
        let ownTable = color == 1 ? Self.zBlack : Self.zWhite
        let enemyTable = color == 1 ? Self.zWhite : Self.zBlack
        zobristKey ^= ownTable[p]
        for s in captured { zobristKey ^= enemyTable[s] }

        // 简单劫：单子提单子，且落子后成单独一手仅剩一口气
        if captured.count == 1 {
            let own = GoGame.floodGroup(board, start: p, boardSize: boardSize, stopAt: 0, scratch: &scratch)
            koPoint = (own.stones.count == 1 && own.libs.count == 1) ? captured[0] : -1
        } else {
            koPoint = -1
        }
        consecutivePasses = 0
        lastPoint = p
        togglePlayer()
        ply += 1
    }

    mutating func togglePlayer() {
        zobristKey ^= Self.zTurn
        currentPlayer = 1 - currentPlayer
    }

    // MARK: 计分

    /// 数子法估分（含死子启发）：活子数 + 独占围空。
    /// 死子判定：少于两个真眼的群视为死子，从盘面移除（其位置自然并入对方地域，
    /// 等价于「计入对方提子」后的地域归属）。
    public func computeAreaScore() -> (black: Double, white: Double) {
        GoGame.areaScore(board: board, boardSize: boardSize)
    }

    static func areaScore(board: [UInt8], boardSize: Int) -> (black: Double, white: Double) {
        let n = boardSize * boardSize
        var b = board
        var groupMark = [Int32](repeating: 0, count: n)
        var eyeMark = [Int32](repeating: 0, count: n)
        var stack: [Int] = []
        var gen: Int32 = 0

        // 1. 找出所有棋子群并统计真眼数
        var groupStones: [[Int]] = []
        var groupEyes: [Int] = []
        for i in 0..<n where b[i] != 0 && groupMark[i] == 0 {
            let color = b[i]
            gen += 1
            groupMark[i] = gen
            stack.removeAll(keepingCapacity: true)
            stack.append(i)
            var stones: [Int] = []
            while let p = stack.popLast() {
                stones.append(p)
                for q in GoGame.orthNeighbors(of: p, boardSize: boardSize) where b[q] == color {
                    if groupMark[q] != gen {
                        groupMark[q] = gen
                        stack.append(q)
                    }
                }
            }
            // 真眼：与本群相邻的空点，四邻全为己色且八邻中己色 ≥ 5
            var eyes = 0
            gen += 1
            for s in stones {
                for q in GoGame.orthNeighbors(of: s, boardSize: boardSize) where b[q] == 0 {
                    if eyeMark[q] != gen {
                        eyeMark[q] = gen
                        if GoGame.isTrueEye(q, color: color, board: b, boardSize: boardSize) {
                            eyes += 1
                        }
                    }
                }
            }
            groupStones.append(stones)
            groupEyes.append(eyes)
        }

        // 2. 死子移除（少于两个真眼的群）
        for gi in 0..<groupStones.count where groupEyes[gi] < 2 {
            for s in groupStones[gi] { b[s] = 0 }
        }

        // 3. 数子：活子 + 独占围空（空域按边界颜色归属，双边接壤为公气不计分）
        var black = 0.0
        var white = 0.0
        var regionMark = [Int32](repeating: 0, count: n)
        gen = 0
        for i in 0..<n {
            if b[i] == 1 {
                black += 1
            } else if b[i] == 2 {
                white += 1
            } else if regionMark[i] == 0 {
                gen += 1
                regionMark[i] = gen
                stack.removeAll(keepingCapacity: true)
                stack.append(i)
                var size = 0
                var touchBlack = false
                var touchWhite = false
                while let p = stack.popLast() {
                    size += 1
                    for q in GoGame.orthNeighbors(of: p, boardSize: boardSize) {
                        let v = b[q]
                        if v == 0 {
                            if regionMark[q] != gen {
                                regionMark[q] = gen
                                stack.append(q)
                            }
                        } else if v == 1 {
                            touchBlack = true
                        } else {
                            touchWhite = true
                        }
                    }
                }
                if touchBlack && !touchWhite {
                    black += Double(size)
                } else if touchWhite && !touchBlack {
                    white += Double(size)
                }
            }
        }
        return (black, white)
    }

    // MARK: 核心算法（静态工具，供 play / legalMoves / MCTS 共用）

    static func orthNeighbors(of p: Int, boardSize: Int) -> [Int] {
        let r = p / boardSize
        let c = p - r * boardSize
        var out: [Int] = []
        if r > 0 { out.append(p - boardSize) }
        if r < boardSize - 1 { out.append(p + boardSize) }
        if c > 0 { out.append(p - 1) }
        if c < boardSize - 1 { out.append(p + 1) }
        return out
    }

    /// 点到棋盘边的距离（行 / 列方向取小）
    static func edgeDistance(of p: Int, boardSize: Int) -> Int {
        let r = p / boardSize
        let c = p - r * boardSize
        return min(min(r, boardSize - 1 - r), min(c, boardSize - 1 - c))
    }

    /// 同色连通群 flood fill。
    /// stopAt > 0 时，气数达到 stopAt 即提前返回（此时 stones / libs 不完整，
    /// 只能用于「是否至少 stopAt 口气」的判断）。
    static func floodGroup(_ board: [UInt8], start: Int, boardSize: Int,
                           stopAt: Int, scratch: inout GoScratch) -> (stones: [Int], libs: [Int]) {
        let color = board[start]
        assert(color != 0, "floodGroup 起点必须是棋子")
        scratch.gen &+= 1
        let gen = scratch.gen
        var stones: [Int] = []
        var libs: [Int] = []
        scratch.mark[start] = gen
        scratch.stack.removeAll(keepingCapacity: true)
        scratch.stack.append(start)
        while let p = scratch.stack.popLast() {
            stones.append(p)
            let r = p / boardSize
            let c = p - r * boardSize
            if r > 0 {
                let q = p - boardSize
                let v = board[q]
                if v == 0 {
                    if scratch.libMark[q] != gen { scratch.libMark[q] = gen; libs.append(q) }
                } else if v == color && scratch.mark[q] != gen {
                    scratch.mark[q] = gen
                    scratch.stack.append(q)
                }
            }
            if r < boardSize - 1 {
                let q = p + boardSize
                let v = board[q]
                if v == 0 {
                    if scratch.libMark[q] != gen { scratch.libMark[q] = gen; libs.append(q) }
                } else if v == color && scratch.mark[q] != gen {
                    scratch.mark[q] = gen
                    scratch.stack.append(q)
                }
            }
            if c > 0 {
                let q = p - 1
                let v = board[q]
                if v == 0 {
                    if scratch.libMark[q] != gen { scratch.libMark[q] = gen; libs.append(q) }
                } else if v == color && scratch.mark[q] != gen {
                    scratch.mark[q] = gen
                    scratch.stack.append(q)
                }
            }
            if c < boardSize - 1 {
                let q = p + 1
                let v = board[q]
                if v == 0 {
                    if scratch.libMark[q] != gen { scratch.libMark[q] = gen; libs.append(q) }
                } else if v == color && scratch.mark[q] != gen {
                    scratch.mark[q] = gen
                    scratch.stack.append(q)
                }
            }
            if stopAt > 0 && libs.count >= stopAt { return (stones, libs) }
        }
        return (stones, libs)
    }

    /// 空点 p 是否为 color 方的真眼：四邻全为己色，且八邻（盘内点）中己色 ≥ 5
    static func isTrueEye(_ p: Int, color: UInt8, board: [UInt8], boardSize: Int) -> Bool {
        let r = p / boardSize
        let c = p - r * boardSize
        var orthAllOwn = true
        var ownCount = 0
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let nr = r + dr
                let nc = c + dc
                guard nr >= 0 && nr < boardSize && nc >= 0 && nc < boardSize else { continue }
                let own = board[nr * boardSize + nc] == color
                if own { ownCount += 1 }
                if dr == 0 || dc == 0 {
                    if !own { orthAllOwn = false }
                }
            }
        }
        return orthAllOwn && ownCount >= 5
    }

    /// p 对 color 是否为合法落点（空位 + 劫禁 + 自杀检查；能提子则不属自杀）
    static func isLegalPoint(_ p: Int, color: UInt8, board: [UInt8], boardSize: Int,
                             koPoint: Int, scratch: inout GoScratch) -> Bool {
        if board[p] != 0 || p == koPoint { return false }
        // 快路径：有空邻则必有气
        for q in orthNeighbors(of: p, boardSize: boardSize) where board[q] == 0 { return true }
        var b = board
        b[p] = color
        let enemy = color ^ 3
        for q in orthNeighbors(of: p, boardSize: boardSize) where b[q] == enemy {
            let g = floodGroup(b, start: q, boardSize: boardSize, stopAt: 3, scratch: &scratch)
            if g.libs.isEmpty { return true } // 能提子
        }
        let own = floodGroup(b, start: p, boardSize: boardSize, stopAt: 2, scratch: &scratch)
        return !own.libs.isEmpty
    }

    /// 就地为 color 在 p 落子（要求 board[p] == 0）。
    /// 提掉无气的相邻敌群；无提子且己群无气视为自杀，恢复 board[p] = 0 并返回非法。
    static func playInPlace(_ p: Int, color: UInt8, board: inout [UInt8], boardSize: Int,
                            scratch: inout GoScratch) -> (legal: Bool, captured: [Int]) {
        let enemy = color ^ 3
        board[p] = color
        var captured: [Int] = []
        for q in orthNeighbors(of: p, boardSize: boardSize) where board[q] == enemy {
            let g = floodGroup(board, start: q, boardSize: boardSize, stopAt: 3, scratch: &scratch)
            if g.libs.isEmpty {
                for s in g.stones { board[s] = 0 }
                captured.append(contentsOf: g.stones)
            }
        }
        if captured.isEmpty {
            let own = floodGroup(board, start: p, boardSize: boardSize, stopAt: 2, scratch: &scratch)
            if own.libs.isEmpty {
                board[p] = 0 // 自杀：恢复原状
                return (false, [])
            }
        }
        return (true, captured)
    }
}

// MARK: - MCTS

/// MCTS 节点。wins 相对「执行本节点着法的玩家」（即父节点的行棋方）。
final class GoMCTSNode {
    let game: GoGame
    let move: GoGame.GoMove?
    let playerJustMoved: Int
    var visits: Int
    var wins: Double
    var children: [GoMCTSNode] = []
    var untried: [GoGame.GoMove]

    init(game: GoGame, move: GoGame.GoMove?, playerJustMoved: Int,
         untried: [GoGame.GoMove], priorWins: Double, priorVisits: Int) {
        self.game = game
        self.move = move
        self.playerJustMoved = playerJustMoved
        self.untried = untried
        self.visits = priorVisits
        self.wins = priorWins
    }
}

/// 围棋 MCTS（UCB1，C = √2；单线程）。
enum GoMCTS {
    static let explorationC: Double = sqrt(2.0)
    /// 先验虚拟访问数：给「三线以上」「非虚着」着法少量先验，稳定开局方向
    static let priorVisits = 8

    static func priorMean(for move: GoGame.GoMove, boardSize: Int) -> Double {
        if move == .pass { return 0.45 }
        let d = GoGame.edgeDistance(of: Int(move.point), boardSize: boardSize)
        switch d {
        case 0: return 0.30
        case 1: return 0.38
        default: return 0.52
        }
    }

    static func shuffle(_ moves: [GoGame.GoMove], rng: inout SplitMix64) -> [GoGame.GoMove] {
        var arr = moves
        var i = arr.count - 1
        while i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            arr.swapAt(i, j)
            i -= 1
        }
        return arr
    }

    /// 主搜索。返回访问数最多的根着法与根节点胜率估计（0..1，根行棋方视角）。
    static func run(root game: GoGame, rootMoves: [GoGame.GoMove], sims: Int,
                    deadline: Date, rng: inout SplitMix64) -> (move: GoGame.GoMove, winRate: Double, nodes: Int) {
        let rootNode = GoMCTSNode(game: game, move: nil, playerJustMoved: -1,
                                  untried: shuffle(rootMoves, rng: &rng),
                                  priorWins: 0, priorVisits: 0)
        var nodeCount = 1
        var scratch = GoScratch(boardSize: game.boardSize)

        for sim in 1...sims {
            if sim % 16 == 0 && Date() > deadline { break } // 软时限：超时立即返回当前最优

            // 1) 选择：UCB1
            var node = rootNode
            var path: [GoMCTSNode] = [rootNode]
            while node.untried.isEmpty && !node.children.isEmpty {
                let logN = log(Double(node.visits + 1))
                var best = node.children[0]
                var bestScore = -Double.infinity
                for c in node.children {
                    let s = c.wins / Double(c.visits) + explorationC * sqrt(logN / Double(c.visits))
                    if s > bestScore { bestScore = s; best = c }
                }
                node = best
                path.append(node)
            }

            // 2) 扩展：逐步展开一个未扩展着法
            if !node.untried.isEmpty {
                let m = node.untried.removeLast()
                var childGame = node.game
                try? childGame.playInternal(m, scratch: &scratch)
                let child = GoMCTSNode(game: childGame, move: m, playerJustMoved: node.game.currentPlayer,
                                       untried: shuffle(childGame.legalMoves(), rng: &rng),
                                       priorWins: priorMean(for: m, boardSize: childGame.boardSize) * Double(priorVisits),
                                       priorVisits: priorVisits)
                node.children.append(child)
                nodeCount += 1
                node = child
                path.append(child)
            }

            // 3) 模拟：playout，终局用数子法估分（与 computeAreaScore 同一函数）
            let areas = playout(from: node.game, rng: &rng, scratch: &scratch)
            let winner: Int = (areas.black > areas.white + GoGame.komi) ? 0 : 1

            // 4) 回传
            for nd in path {
                nd.visits += 1
                if nd.playerJustMoved == winner { nd.wins += 1 }
            }
        }

        // 根节点：访问数最多的着法
        var bestChild = rootNode.children[0]
        for c in rootNode.children where c.visits > bestChild.visits { bestChild = c }
        var totalVisits = 0.0
        var totalWins = 0.0
        for c in rootNode.children {
            totalVisits += Double(c.visits)
            totalWins += c.wins
        }
        let winRate = totalVisits > 0 ? totalWins / totalVisits : 0.5
        return (bestChild.move!, winRate, nodeCount)
    }

    /// playout：从 start 局面就地破坏式模拟至双虚着或 3×size² 手上限。
    /// 策略：提对方 1 气群 > 逃自己 1 气群 > 随机
    /// （随机阶段：存在距边 ≥2 的空点时跳过一二线，绝不填自己的真眼，避开劫禁与自杀）。
    static func playout(from start: GoGame, rng: inout SplitMix64, scratch: inout GoScratch) -> (black: Double, white: Double) {
        let n = start.boardSize
        let n2 = n * n
        var board = start.board
        var ko = start.koPoint
        var player = start.currentPlayer
        var passes = start.consecutivePasses
        var lastMove = start.lastPoint
        var empties: [Int] = []
        empties.reserveCapacity(n2)
        var interiorEmpties = 0 // 距边 ≥2 的空点数（前盘阶段优先内线）
        for i in 0..<n2 where board[i] == 0 {
            empties.append(i)
            if GoGame.edgeDistance(of: i, boardSize: n) >= 2 { interiorEmpties += 1 }
        }
        var movesLeft = 3 * n2

        while passes < 2 && movesLeft > 0 {
            movesLeft -= 1
            let me = UInt8(player + 1)
            var played: Int? = nil
            var playedIdx: Int? = nil

            // 1) 战术：围绕上一手 —— 提对方 1 气群，或逃自己 1 气群
            if lastMove >= 0 {
                var capCands: [Int] = []
                var escCands: [Int] = []
                var seenLibs: Set<Int> = []
                var roots: [Int] = []
                if board[lastMove] != 0 { roots.append(lastMove) }
                for q in GoGame.orthNeighbors(of: lastMove, boardSize: n) where board[q] != 0 {
                    roots.append(q)
                }
                for root in roots {
                    let v = board[root]
                    let g = GoGame.floodGroup(board, start: root, boardSize: n, stopAt: 2, scratch: &scratch)
                    if g.libs.count == 1 && !seenLibs.contains(g.libs[0]) {
                        seenLibs.insert(g.libs[0])
                        if v == me { escCands.append(g.libs[0]) } else { capCands.append(g.libs[0]) }
                    }
                }
                var capOK: [Int] = []
                for c in capCands where !GoGame.isTrueEye(c, color: me, board: board, boardSize: n) {
                    if GoGame.isLegalPoint(c, color: me, board: board, boardSize: n, koPoint: ko, scratch: &scratch) {
                        capOK.append(c)
                    }
                }
                if !capOK.isEmpty {
                    played = capOK[Int(rng.next() % UInt64(capOK.count))]
                } else {
                    var escOK: [Int] = []
                    for c in escCands where !GoGame.isTrueEye(c, color: me, board: board, boardSize: n) {
                        var b2 = board
                        let r = GoGame.playInPlace(c, color: me, board: &b2, boardSize: n, scratch: &scratch)
                        guard r.legal else { continue }
                        if !r.captured.isEmpty {
                            escOK.append(c) // 逃叫吃同时提子
                            continue
                        }
                        let own = GoGame.floodGroup(b2, start: c, boardSize: n, stopAt: 2, scratch: &scratch)
                        if own.libs.count >= 2 { escOK.append(c) }
                    }
                    if !escOK.isEmpty {
                        played = escOK[Int(rng.next() % UInt64(escOK.count))]
                    }
                }
            }

            // 2) 随机：内线优先，避真眼 / 劫禁 / 自杀
            if played == nil && !empties.isEmpty {
                var tries = 0
                while played == nil && tries < 24 {
                    tries += 1
                    let k = Int(rng.next() % UInt64(empties.count))
                    let p = empties[k]
                    if interiorEmpties > 0 && GoGame.edgeDistance(of: p, boardSize: n) < 2 { continue }
                    if p == ko { continue }
                    if GoGame.isTrueEye(p, color: me, board: board, boardSize: n) { continue }
                    if GoGame.isLegalPoint(p, color: me, board: board, boardSize: n, koPoint: ko, scratch: &scratch) {
                        played = p
                        playedIdx = k
                    }
                }
            }

            // 3) 兜底线性扫描（先带内线偏好，再放开）
            if played == nil && !empties.isEmpty {
                for relaxBias in [false, true] {
                    for p in empties {
                        if !relaxBias && interiorEmpties > 0 && GoGame.edgeDistance(of: p, boardSize: n) < 2 { continue }
                        if p == ko { continue }
                        if GoGame.isTrueEye(p, color: me, board: board, boardSize: n) { continue }
                        if GoGame.isLegalPoint(p, color: me, board: board, boardSize: n, koPoint: ko, scratch: &scratch) {
                            played = p
                            break
                        }
                    }
                    if played != nil { break }
                }
            }

            // 4) 执行或虚着
            if let p = played {
                let r = GoGame.playInPlace(p, color: me, board: &board, boardSize: n, scratch: &scratch)
                // 维护空点表（O(1) swap-remove，优先用已知下标）
                if let k = playedIdx, k < empties.count, empties[k] == p {
                    let lastIdx = empties.count - 1
                    if k != lastIdx { empties[k] = empties[lastIdx] }
                    empties.removeLast()
                } else if let fi = empties.firstIndex(of: p) {
                    let lastIdx = empties.count - 1
                    if fi != lastIdx { empties[fi] = empties[lastIdx] }
                    empties.removeLast()
                }
                if GoGame.edgeDistance(of: p, boardSize: n) >= 2 { interiorEmpties -= 1 }
                for cp in r.captured {
                    empties.append(cp)
                    if GoGame.edgeDistance(of: cp, boardSize: n) >= 2 { interiorEmpties += 1 }
                }
                // 劫
                if r.captured.count == 1 {
                    let own = GoGame.floodGroup(board, start: p, boardSize: n, stopAt: 0, scratch: &scratch)
                    ko = (own.stones.count == 1 && own.libs.count == 1) ? r.captured[0] : -1
                } else {
                    ko = -1
                }
                passes = 0
                lastMove = p
            } else {
                passes += 1
                ko = -1
                lastMove = -1
            }
            player ^= 1
        }
        return GoGame.areaScore(board: board, boardSize: n)
    }
}

// MARK: - AI 包装

/// 围棋 AI（MCTS）
public enum GoAI {
    /// 各难度每步模拟次数
    static let simulationsFor: [AIDifficulty: Int] = [
        .easy: 400, .medium: 2500, .hard: 10_000, .veryHard: 30_000, .celestial: 90_000
    ]

    public static func bestMove(in game: GoGame, difficulty: AIDifficulty, rng: SplitMix64? = nil) -> SearchResult<GoGame.GoMove> {
        if game.isOver {
            return SearchResult(move: nil, value: 0, depth: 0, nodes: 0)
        }
        var rng = rng ?? SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1_000_000))
        let profile = DifficultyProfile.for(difficulty)
        let sims = simulationsFor[difficulty] ?? 400
        let deadline = Date().addingTimeInterval(Double(profile.timeBudgetMs) / 1000.0)
        let rootMoves = game.legalMoves()
        guard !rootMoves.isEmpty else {
            return SearchResult(move: nil, value: 0, depth: 0, nodes: 0)
        }
        if rootMoves.count == 1 {
            // 只剩虚着
            return SearchResult(move: rootMoves[0], value: 0.5, depth: 0, nodes: 0)
        }
        let r = GoMCTS.run(root: game, rootMoves: rootMoves, sims: sims, deadline: deadline, rng: &rng)
        return SearchResult(move: r.move, value: r.winRate, depth: 0, nodes: r.nodes)
    }
}

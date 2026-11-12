import Foundation

// MARK: - 棋种与难度

/// 七种棋
public enum GameID: String, CaseIterable, Codable, Sendable {
    case go, shogi, xiangqi, chess, draughts, gomoku, reversi

    public var displayName: String {
        switch self {
        case .go: return "围棋"
        case .shogi: return "将棋"
        case .xiangqi: return "中国象棋"
        case .chess: return "国际象棋"
        case .draughts: return "国际跳棋"
        case .gomoku: return "五子棋"
        case .reversi: return "黑白棋"
        }
    }
}

/// AI 难度五档：低 / 中 / 高 / 超高 / 天人
public enum AIDifficulty: String, CaseIterable, Codable, Sendable {
    case easy, medium, hard, veryHard, celestial

    public var displayName: String {
        switch self {
        case .easy: return "低"
        case .medium: return "中"
        case .hard: return "高"
        case .veryHard: return "超高"
        case .celestial: return "天人"
        }
    }
}

/// 难度 → 搜索参数。
/// evaluate() 的单位约为「兵 = 1.0」，rootMargin 用同一单位。
public struct DifficultyProfile: Sendable, Equatable {
    public var maxDepth: Int        // 迭代加深深度上限（层）
    public var timeBudgetMs: Int    // 单步思考软时限
    public var rootMargin: Double   // 根节点候选容差（越大越容易走出次优）
    public var pickSpread: Double   // 0=总选最优；1=在候选中均匀随机
    public var useTT: Bool

    public init(maxDepth: Int, timeBudgetMs: Int, rootMargin: Double, pickSpread: Double, useTT: Bool) {
        self.maxDepth = maxDepth
        self.timeBudgetMs = timeBudgetMs
        self.rootMargin = rootMargin
        self.pickSpread = pickSpread
        self.useTT = useTT
    }

    /// 基准档位（分支大的棋种可用 depthScale 调整）
    public static func `for`(_ d: AIDifficulty, depthScale: Double = 1.0) -> DifficultyProfile {
        switch d {
        case .easy:      return .init(maxDepth: max(1, Int((2  * depthScale).rounded())), timeBudgetMs: 300,  rootMargin: 3.0, pickSpread: 1.0, useTT: false)
        case .medium:    return .init(maxDepth: max(2, Int((4  * depthScale).rounded())), timeBudgetMs: 900,  rootMargin: 0.45, pickSpread: 0.3, useTT: true)
        case .hard:      return .init(maxDepth: max(3, Int((8  * depthScale).rounded())), timeBudgetMs: 2200, rootMargin: 0.0, pickSpread: 0.0, useTT: true)
        case .veryHard:  return .init(maxDepth: max(4, Int((12 * depthScale).rounded())), timeBudgetMs: 4200, rootMargin: 0.0, pickSpread: 0.0, useTT: true)
        case .celestial: return .init(maxDepth: 64, timeBudgetMs: 6000, rootMargin: 0.0, pickSpread: 0.0, useTT: true)
        }
    }
}

// MARK: - 随机数（可复现）

/// SplitMix64：轻量确定性随机，用于 Zobrist 表与难度放水
public struct SplitMix64: Sendable {
    public var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// Zobrist 哈希辅助：确定性生成随机键表
public enum Zobrist {
    public static func table(_ count: Int, seed: UInt64) -> [UInt64] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in rng.next() }
    }
}

// MARK: - 游戏协议

public enum MoveError: Error, Sendable {
    case illegalMove
    case gameIsOver
}

/// 双人对局协议。行列坐标统一为 UInt8 索引（各棋种自定义编码）。
/// 玩家统一用 0 / 1 表示；0 为先手方（围棋/五子/黑白棋=黑，将棋=先手，象棋=红，国象/跳棋=白）。
public protocol BoardGame {
    associatedtype Move: Hashable & Sendable

    init()

    /// 当前行棋方（0 / 1）
    var currentPlayer: Int { get }
    /// 已走步数（含虚着）
    var ply: Int { get }

    func legalMoves() -> [Move]
    mutating func play(_ move: Move) throws

    var isOver: Bool { get }
    /// 终局分：1.0 胜 / 0.5 和 / 0.0 负（相对传入 player）；未终局返回 nil
    func score(for player: Int) -> Double?

    /// 静态评估：正值利当前行棋方，单位约为「兵 = 1.0」
    func evaluate() -> Double

    /// Zobrist 哈希（增量维护），用于置换表
    var zobristKey: UInt64 { get }

    func copy() -> Self
}

public extension BoardGame {
    /// 走子排序提示，越大越优先搜索（例如 MVV-LVA：吃大子用小子得高分）
    func orderHint(for move: Move) -> Int { 0 }
    /// 是否为战术着法（吃子等）——静态搜索只扩展战术着法
    func isTactical(_ move: Move) -> Bool { false }
    /// 当前行棋方是否被将军（被将军时静态搜索需搜全部应着）
    var isInCheck: Bool { false }
}

// MARK: - 终局分换算

public enum GameScore {
    /// 协议分（1/0.5/0）→ 搜索值（当前行棋方视角），胜方偏好更快取胜
    public static func searchValue(score s: Double, ply: Int) -> Double {
        let winScale = 1_000_000.0
        var v = (s - 0.5) * 2 * winScale
        if v > 0 { v -= Double(ply) }        // 赢要快
        else if v < 0 { v += Double(ply) }   // 输要慢
        return v
    }
}

import Foundation

// MARK: - 置换表

struct TTEntry<M: Hashable> {
    var depth: Int
    var value: Double
    var flag: UInt8 // 0 精确, 1 下界(≥), 2 上界(≤)
    var best: M?
}

// MARK: - 搜索结果

public struct SearchResult<Move: Sendable>: Sendable {
    public let move: Move?
    public let value: Double      // 当前行棋方视角
    public let depth: Int
    public let nodes: Int
}

// MARK: - 通用 α-β 搜索器

/// negamax + 迭代加深 + 置换表 + 静态搜索 + 时间控制。
/// 适用于所有 BoardGame 实现（围棋除外，围棋走 MCTS）。
public enum AlphaBetaSearch {

    public static func bestMove<G: BoardGame>(
        in game: G,
        profile: DifficultyProfile,
        rng: SplitMix64 = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1_000_000))
    ) -> SearchResult<G.Move> where G.Move: Comparable {
        let start = Date()
        var ctx = Context<G>(deadline: start.addingTimeInterval(Double(profile.timeBudgetMs) / 1000.0))

        let rootMoves = game.legalMoves()
        guard !rootMoves.isEmpty else {
            return SearchResult(move: nil, value: 0, depth: 0, nodes: 0)
        }
        guard rootMoves.count > 1 || game.isOver == false else {
            return SearchResult(move: rootMoves[0], value: 0, depth: 0, nodes: 0)
        }

        // 根走子初始排序（战术着法优先）
        var ordered = rootMoves.sorted { game.orderHint(for: $0) > game.orderHint(for: $1) }
        var lastScores: [G.Move: Double] = [:]
        var bestOverall = ordered[0]
        var bestValueOverall = -Double.infinity
        var completedDepth = 0
        var nodesUsed = 0

        var depth = 1
        while depth <= profile.maxDepth {
            var alpha = -Double.infinity
            var beta = Double.infinity
            var thisDepthScores: [G.Move: Double] = [:]
            var bestThisDepth = ordered[0]
            var bestValThis = -Double.infinity
            var aborted = false

            for m in ordered {
                var child = game
                do { try child.play(m) } catch { continue }
                let v = -ctx.negamax(&child, depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1)
                if ctx.aborted { aborted = true; break }
                nodesUsed = ctx.nodes
                thisDepthScores[m] = v
                if v > bestValThis {
                    bestValThis = v
                    bestThisDepth = m
                }
                if v > alpha { alpha = v }
            }

            if aborted && completedDepth > 0 { break }
            if aborted && thisDepthScores.isEmpty { break }

            // 完成（或部分完成且已是首层）的本层结果
            if !thisDepthScores.isEmpty {
                lastScores = thisDepthScores
                bestOverall = bestThisDepth
                bestValueOverall = bestValThis
                completedDepth = depth
                // 下一轮迭代：把本层最优排最前
                ordered.sort { (thisDepthScores[$1] ?? -Double.infinity) < (thisDepthScores[$0] ?? -Double.infinity) }
            }
            if aborted { break }
            // 确定性胜负已定，无需更深
            if abs(bestValThis) > 900_000 { break }
            depth += 1
        }

        // 根节点选择：按容差 + 放水概率做有限随机，制造低难度可乘之机
        let chosen = selectRootMove(scores: lastScores,
                                    fallback: bestOverall,
                                    fallbackValue: bestValueOverall,
                                    rootMoves: ordered,
                                    margin: profile.rootMargin,
                                    spread: profile.pickSpread,
                                    rng: rng)

        return SearchResult(move: chosen,
                            value: bestValueOverall,
                            depth: completedDepth,
                            nodes: nodesUsed)
    }

    static func selectRootMove<M: Hashable>(scores: [M: Double],
                                            fallback: M,
                                            fallbackValue: Double,
                                            rootMoves: [M],
                                            margin: Double,
                                            spread: Double,
                                            rng: SplitMix64) -> M {
        var rng = rng
        guard !scores.isEmpty else { return fallback }
        if margin > 0 || spread > 0 {
            var candidates = scores.filter { $0.value >= fallbackValue - margin }.map(\.key)
            if candidates.isEmpty { candidates = [fallback] }
            if spread > 0, rng.nextDouble() < spread, candidates.count > 1 {
                let i = Int(rng.next() % UInt64(candidates.count))
                return candidates[i]
            }
            // 容差内取最优（字典序稳定）
            return candidates.max { scores[$0]! < scores[$1]! } ?? fallback
        }
        return fallback
    }
}

extension AlphaBetaSearch {

    final class Context<G: BoardGame> {
        var tt: [UInt64: TTEntry<G.Move>] = [:]
        var nodes = 0
        let deadline: Date
        var aborted = false
        let winScale = 1_000_000.0

        init(deadline: Date) {
            self.deadline = deadline
        }

        func negamax(_ game: inout G, depth: Int, alpha: Double, beta: Double, ply: Int) -> Double {
            nodes += 1
            if nodes & 511 == 0, Date() > deadline {
                aborted = true
                return 0
            }

            if game.isOver {
                if let s = game.score(for: game.currentPlayer) {
                    return GameScore.searchValue(score: s, ply: ply)
                }
                return game.evaluate()
            }

            let key = game.zobristKey
            if let e = tt[key], e.depth >= depth {
                switch e.flag {
                case 0: return e.value
                case 1: if e.value >= beta { return e.value }
                case 2: if e.value <= alpha { return e.value }
                default: break
                }
            }

            if depth <= 0 {
                let v = quiescence(&game, alpha: alpha, beta: beta, ply: ply, qdepth: 0)
                storeTT(key, depth: 0, value: v, alpha: alpha, beta: beta, best: nil)
                return v
            }

            var moves = game.legalMoves()
            if moves.isEmpty {
                return game.evaluate()
            }
            let ttBest = tt[key]?.best
            moves.sort {
                let a = ($0 == ttBest) ? Int(1e9) : game.orderHint(for: $0)
                let b = ($1 == ttBest) ? Int(1e9) : game.orderHint(for: $1)
                return a > b
            }

            var alpha = alpha
            var best = -Double.infinity
            var bestMove: G.Move?
            for m in moves {
                var child = game
                do { try child.play(m) } catch { continue }
                let v = -negamax(&child, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                if aborted { return 0 }
                if v > best {
                    best = v
                    bestMove = m
                }
                if v > alpha { alpha = v }
                if alpha >= beta { break }
            }
            storeTT(key, depth: depth, value: best, alpha: alpha, beta: beta, best: bestMove)
            return best
        }

        /// 静态搜索：只扩展战术着法；被将军时扩展全部应着
        func quiescence(_ game: inout G, alpha: Double, beta: Double, ply: Int, qdepth: Int) -> Double {
            nodes += 1
            if nodes & 511 == 0, Date() > deadline {
                aborted = true
                return 0
            }
            let stand = game.evaluate()
            if stand >= beta { return stand }
            var alpha = max(alpha, stand)
            if qdepth >= 8 { return stand }

            let all = game.isInCheck
            var moves = game.legalMoves().filter { all || game.isTactical($0) }
            if all && moves.isEmpty {
                // 无应着且被将军 → 由协议层终局判定；此处防御性返回
                if game.isOver, let s = game.score(for: game.currentPlayer) {
                    return GameScore.searchValue(score: s, ply: ply)
                }
                return stand
            }
            if moves.isEmpty { return stand }
            moves.sort { game.orderHint(for: $0) > game.orderHint(for: $1) }

            var best = stand
            for m in moves {
                var child = game
                do { try child.play(m) } catch { continue }
                let v = -quiescence(&child, alpha: -beta, beta: -alpha, ply: ply + 1, qdepth: qdepth + 1)
                if aborted { return 0 }
                if v > best { best = v }
                if best > alpha { alpha = best }
                if alpha >= beta { break }
            }
            return best
        }

        func storeTT(_ key: UInt64, depth: Int, value: Double, alpha: Double, beta: Double, best: G.Move?) {
            var flag: UInt8 = 0
            if value <= alpha { flag = 2 }
            else if value >= beta { flag = 1 }
            tt[key] = TTEntry(depth: depth, value: value, flag: flag, best: best)
        }
    }
}

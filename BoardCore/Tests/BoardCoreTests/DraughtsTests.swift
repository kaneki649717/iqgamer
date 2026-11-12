import XCTest
@testable import BoardCore

final class DraughtsTests: XCTestCase {

    // MARK: - 摆盘工具

    /// 用 (row, col, piece) 三元组直接摆盘
    private static func board(_ pieces: [(Int, Int, UInt8)]) -> [UInt8] {
        var s = [UInt8](repeating: 0, count: 100)
        for (r, c, p) in pieces { s[r * 10 + c] = p }
        return s
    }

    /// 用 index 序列构造着法
    private static func mv(_ sqs: [Int]) -> Draughts.DraughtsMove {
        Draughts.DraughtsMove(path: sqs.map { UInt8($0) })
    }

    // MARK: - 初始局面

    func testInitialState() {
        let g = Draughts()
        XCTAssertEqual(g.currentPlayer, 0)
        XCTAssertEqual(g.ply, 0)
        XCTAssertFalse(g.isInCheck)
        var whiteMen = 0, blackMen = 0
        for i in 0..<100 {
            if g.squares[i] == Draughts.Piece.whiteMan { whiteMen += 1 }
            if g.squares[i] == Draughts.Piece.blackMan { blackMen += 1 }
        }
        XCTAssertEqual(whiteMen, 20)
        XCTAssertEqual(blackMen, 20)
        // 开局：row 3 的 5 枚白兵各 1~2 步，共 9 步
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 9)
        for m in moves {
            XCTAssertEqual(m.path.count, 2)
            XCTAssertEqual(Int(m.path[0]) / 10, 3, "开局只有 row 3 的兵能动")
            XCTAssertEqual(Int(m.path[1]) / 10, 4, "白棋向 row 增大方向前进")
        }
        // 双方完全对称 → 评估应为 0
        XCTAssertEqual(g.evaluate(), 0.0, accuracy: 1e-9)
    }

    // MARK: - 有吃必吃

    func testMustCapture() {
        // 白兵 (5,2) 可跳吃黑兵 (6,3)；另一白兵 (1,0) 只有平移
        let g = Draughts(squares: Self.board([
            (5, 2, Draughts.Piece.whiteMan),
            (1, 0, Draughts.Piece.whiteMan),
            (6, 3, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path, [52, 74] as [UInt8])
        XCTAssertFalse(moves.contains(Self.mv([10, 21])), "有吃必吃：平移着法不得出现")
    }

    // MARK: - 最大吃子（majority rule）

    func testMajorityRule() {
        // 白兵 (5,2)：向左吃 (6,1) 只吃 1 枚；向右吃 (6,3) 再吃 (8,5) 共 2 枚。
        // 落点 (9,6) 为底线：停下升王，以王看已无可续吃 → 链到此为止。
        var g = Draughts(squares: Self.board([
            (5, 2, Draughts.Piece.whiteMan),
            (6, 3, Draughts.Piece.blackMan),
            (6, 1, Draughts.Piece.blackMan),
            (8, 5, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path, [52, 74, 96] as [UInt8])
        XCTAssertFalse(moves.contains(Self.mv([52, 70])), "必须走吃子数最多的路线")
        XCTAssertTrue(g.isTactical(moves[0]))
        XCTAssertFalse(g.isTactical(Self.mv([52, 43]))) // 兵 1 格平移不是战术着法
        XCTAssertEqual(g.orderHint(for: moves[0]), 200)
        // 走子结果：升王、清子、换手
        try? g.play(moves[0])
        XCTAssertEqual(g.squares[96], Draughts.Piece.whiteKing)
        XCTAssertEqual(g.squares[63], Draughts.Piece.empty)
        XCTAssertEqual(g.squares[85], Draughts.Piece.empty)
        XCTAssertEqual(g.squares[52], Draughts.Piece.empty)
        XCTAssertEqual(g.currentPlayer, 1)
    }

    // MARK: - 连吃不可重复跳同一子 / Turkish strike

    func testTurkishStrikeNoRejump() {
        // 白王 (3,6)；黑兵 (5,4)、(2,7)。
        // 跳吃 (5,4) 可落 (6,3)/(7,2)/(8,1)/(9,0)，跳吃 (2,7) 可落 (1,8)/(0,9)，
        // 共 6 条单吃链。落子后被跳子仍在盘上：不可再跳它，
        // 也不能穿过它沿同一条对角线继续飞去吃另一枚子。
        let g = Draughts(squares: Self.board([
            (3, 6, Draughts.Piece.whiteKing),
            (5, 4, Draughts.Piece.blackMan),
            (2, 7, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 6)
        let paths = Set(moves.map { $0.path })
        XCTAssertTrue(paths.contains([36, 63] as [UInt8]))
        XCTAssertTrue(paths.contains([36, 72] as [UInt8]))
        XCTAssertTrue(paths.contains([36, 81] as [UInt8]))
        XCTAssertTrue(paths.contains([36, 90] as [UInt8]))
        XCTAssertTrue(paths.contains([36, 18] as [UInt8]))
        XCTAssertTrue(paths.contains([36, 9] as [UInt8]))
        // 不存在穿过已跳子（或再次跳它）得到的 3 段链
        XCTAssertFalse(paths.contains([36, 63, 18] as [UInt8]))
        XCTAssertFalse(paths.contains([36, 72, 18] as [UInt8]))
        XCTAssertFalse(paths.contains([36, 81, 18] as [UInt8]))
        XCTAssertFalse(paths.contains([36, 90, 18] as [UInt8]))
        XCTAssertFalse(paths.contains([36, 18, 63] as [UInt8]))
        XCTAssertTrue(moves.allSatisfy { $0.path.count == 2 })
    }

    // MARK: - 飞王

    func testFlyingKingQuietRange() {
        // 白王 (0,1) 沿右下对角线可飞到 (1,2)…(8,9) 共 8 格 + 左下 1 格 = 9 步平移
        let g = Draughts(squares: Self.board([
            (0, 1, Draughts.Piece.whiteKing),
            (9, 0, Draughts.Piece.blackMan),
            (9, 8, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 9)
        let paths = Set(moves.map { $0.path })
        XCTAssertTrue(paths.contains([1, 89] as [UInt8]), "飞王应能远距离平移")
        XCTAssertTrue(paths.contains([1, 10] as [UInt8]))
        XCTAssertTrue(moves.allSatisfy { $0.path.count == 2 })
    }

    func testFlyingKingLongCapture() {
        // 白王 (0,1) 远距离跳吃 (5,6)，可落在其后任意空格 (6,7)/(7,8)/(8,9)
        let g = Draughts(squares: Self.board([
            (0, 1, Draughts.Piece.whiteKing),
            (5, 6, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 3)
        let paths = Set(moves.map { $0.path })
        XCTAssertTrue(paths.contains([1, 67] as [UInt8]))
        XCTAssertTrue(paths.contains([1, 78] as [UInt8]))
        XCTAssertTrue(paths.contains([1, 89] as [UInt8]), "跳过敌子后应能落在其后任意空格")
    }

    func testKingCaptureStopsBeforeSecondPiece() {
        // 黑兵 (3,4) 与 (6,7)：跳过 (3,4) 只能落在 (4,5)/(5,6)，
        // 不得越过第二个子 (6,7)；两个落点各可继续吃 (6,7) → 4 条两吃链。
        let g = Draughts(squares: Self.board([
            (0, 1, Draughts.Piece.whiteKing),
            (3, 4, Draughts.Piece.blackMan),
            (6, 7, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        let expected: Set<[UInt8]> = [
            [1, 45, 78], [1, 45, 89], [1, 56, 78], [1, 56, 89],
        ]
        XCTAssertEqual(Set(moves.map { $0.path }), expected)
        XCTAssertTrue(moves.allSatisfy { $0.path.count == 3 })
    }

    // MARK: - 兵向后吃

    func testManCapturesBackward() {
        // 白兵 (5,4) 向后跳吃 (4,3) 落 (3,2)；(4,5) 为空也不允许向后平移
        let g = Draughts(squares: Self.board([
            (5, 4, Draughts.Piece.whiteMan),
            (4, 3, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path, [54, 32] as [UInt8])
        XCTAssertFalse(moves.contains(Self.mv([54, 45])), "兵不能向后平移")
    }

    // MARK: - 中途升王并继续吃（FMJD 特性）

    func testPromotionDuringCaptureContinuesAsKing() {
        // 白兵 (7,4) 跳 (8,5) 落 (9,6) 底线：停下升王，并以王继续吃 (8,7) 落 (7,8)
        var g = Draughts(squares: Self.board([
            (7, 4, Draughts.Piece.whiteMan),
            (8, 5, Draughts.Piece.blackMan),
            (8, 7, Draughts.Piece.blackMan),
        ]))
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path, [74, 96, 78] as [UInt8], "升王后必须以王继续吃")
        try? g.play(moves[0])
        XCTAssertEqual(g.squares[78], Draughts.Piece.whiteKing, "链中升王，最终以王落定")
        XCTAssertEqual(g.squares[96], Draughts.Piece.empty)
        XCTAssertEqual(g.squares[85], Draughts.Piece.empty)
        XCTAssertEqual(g.squares[87], Draughts.Piece.empty)
        XCTAssertEqual(g.squares[74], Draughts.Piece.empty)
        // 与直接摆出终局局面的 key 一致（含换手键）
        let fresh = Draughts(squares: Self.board([(7, 8, Draughts.Piece.whiteKing)]), currentPlayer: 1)
        XCTAssertEqual(g.zobristKey, fresh.zobristKey)
    }

    func testPromotionByQuietMove() {
        var g = Draughts(squares: Self.board([
            (8, 5, Draughts.Piece.whiteMan),
            (0, 3, Draughts.Piece.blackMan),
        ]))
        XCTAssertTrue(g.legalMoves().contains(Self.mv([85, 96])))
        try? g.play(Self.mv([85, 96]))
        XCTAssertEqual(g.squares[96], Draughts.Piece.whiteKing, "平移到底线应升王")
    }

    // MARK: - 终局判定

    func testNoLegalMovesLoses() {
        // 黑兵 (1,2) 前方被白兵堵死（升王线在前）、身后无子可吃 → 黑无着法判负
        let g = Draughts(squares: Self.board([
            (0, 1, Draughts.Piece.whiteMan),
            (0, 3, Draughts.Piece.whiteMan),
            (1, 2, Draughts.Piece.blackMan),
        ]), currentPlayer: 1)
        XCTAssertTrue(g.legalMoves().isEmpty)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 1), 0.0)
        XCTAssertEqual(g.score(for: 0), 1.0)
    }

    func testNoPiecesLoses() {
        let g = Draughts(squares: Self.board([
            (5, 0, Draughts.Piece.whiteMan),
        ]), currentPlayer: 1)
        XCTAssertTrue(g.isOver)
        XCTAssertTrue(g.legalMoves().isEmpty)
        XCTAssertEqual(g.score(for: 1), 0.0)
        XCTAssertEqual(g.score(for: 0), 1.0)
        XCTAssertThrowsError(try g.play(Self.mv([50, 61])), "终局后走子应抛 gameIsOver")
    }

    // MARK: - 50 半回合和棋

    func testFiftyHalfMoveDraw() {
        // 两个王互不接触，49 个半回合无吃子无兵动后再走一步王 → 和棋
        var g = Draughts(squares: Self.board([
            (0, 1, Draughts.Piece.whiteKing),
            (9, 8, Draughts.Piece.blackKing),
        ]), idles: 49)
        XCTAssertFalse(g.isOver)
        try? g.play(Self.mv([1, 12]))
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 0), 0.5)
        XCTAssertEqual(g.score(for: 1), 0.5)

        // 动兵会重置计数（即使升王）
        var g2 = Draughts(squares: Self.board([
            (8, 3, Draughts.Piece.whiteMan),
            (9, 6, Draughts.Piece.blackKing),
        ]), idles: 49)
        try? g2.play(Self.mv([83, 92]))
        XCTAssertFalse(g2.isOver)
        XCTAssertEqual(g2.idles, 0)
    }

    // MARK: - Zobrist 一致性

    func testZobristMatchesReplay() {
        var rng = SplitMix64(seed: 42)
        var g1 = Draughts()
        var movesPlayed: [Draughts.DraughtsMove] = []
        for _ in 0..<80 {
            if g1.isOver { break }
            let ms = g1.legalMoves()
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try? g1.play(m)
            movesPlayed.append(m)
        }
        var g2 = Draughts()
        for m in movesPlayed { try? g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey)
        XCTAssertEqual(g1.squares, g2.squares)
        XCTAssertEqual(g1.currentPlayer, g2.currentPlayer)
        XCTAssertEqual(g1.idles, g2.idles)
        XCTAssertEqual(g1.ply, g2.ply)
    }

    func testCopyIsIndependent() {
        var g = Draughts()
        let c = g.copy()
        try? c.play(Self.mv([30, 41]))
        XCTAssertEqual(c.ply, 1)
        XCTAssertEqual(g.ply, 0)
        XCTAssertEqual(g.squares[30], Draughts.Piece.whiteMan)
        XCTAssertNotEqual(g.zobristKey, c.zobristKey)
    }

    // MARK: - 非法着法

    func testIllegalMovesThrow() {
        // 有吃必吃时平移非法
        var g = Draughts(squares: Self.board([
            (5, 2, Draughts.Piece.whiteMan),
            (1, 0, Draughts.Piece.whiteMan),
            (6, 3, Draughts.Piece.blackMan),
        ]))
        XCTAssertThrowsError(try g.play(Self.mv([10, 21])))
        // 非最长吃子链非法
        g = Draughts(squares: Self.board([
            (5, 2, Draughts.Piece.whiteMan),
            (6, 3, Draughts.Piece.blackMan),
            (6, 1, Draughts.Piece.blackMan),
            (8, 5, Draughts.Piece.blackMan),
        ]))
        XCTAssertThrowsError(try g.play(Self.mv([52, 70])), "有更长吃子链时不得走短链")
        // 移动对方棋子非法
        XCTAssertThrowsError(try g.play(Self.mv([63, 74])))
        // 落点跨过被吃子
        XCTAssertThrowsError(try g.play(Self.mv([52, 96])))
        // path 不足 2 元素
        XCTAssertThrowsError(try g.play(Self.mv([52])))
    }

    // MARK: - 评估视角

    func testEvaluatePerspective() {
        let g = Draughts(squares: Self.board([
            (5, 4, Draughts.Piece.whiteKing),  // 王 3.2 + 中心 0.05
            (1, 0, Draughts.Piece.blackMan),   // 兵 1.0 + 边线 0.1
        ]))
        XCTAssertGreaterThan(g.evaluate(), 2.0, "当前行棋方为白，应显著为正")
        let g2 = Draughts(squares: Self.board([
            (5, 4, Draughts.Piece.whiteKing),
            (1, 0, Draughts.Piece.blackMan),
        ]), currentPlayer: 1)
        XCTAssertLessThan(g2.evaluate(), -2.0, "换成黑行棋，评估应变号")
    }

    // MARK: - 随机对局终止性

    func testRandomGameTerminates() {
        for seed in [3, 17, 29] {
            var rng = SplitMix64(seed: UInt64(seed))
            var g = Draughts()
            while !g.isOver {
                let ms = g.legalMoves()
                XCTAssertFalse(ms.isEmpty)
                let m = ms[Int(rng.next() % UInt64(ms.count))]
                try? g.play(m)
                XCTAssertLessThan(g.ply, 2100, "游戏未按预期结束（seed=\(seed)）")
            }
            let s = g.score(for: 0)
            XCTAssertNotNil(s)
            XCTAssertTrue([0.0, 0.5, 1.0].contains(s!))
        }
    }

    // MARK: - AI

    func testAIPerformsLegalitySanity() {
        // 有吃必吃局面：唯一着法
        let g = Draughts(squares: Self.board([
            (5, 2, Draughts.Piece.whiteMan),
            (6, 3, Draughts.Piece.blackMan),
        ]))
        let r = DraughtsAI.bestMove(in: g, difficulty: .medium, rng: SplitMix64(seed: 1))
        XCTAssertEqual(r.move, Self.mv([52, 74]), "AI 必须执行强制吃子")
    }

    func testAIBeatsRandomConsistently() {
        for seed in [11, 22, 33] {
            var g = Draughts()
            var aiRng = SplitMix64(seed: 99)
            var rnd = SplitMix64(seed: UInt64(seed))
            while !g.isOver {
                if g.currentPlayer == 0 {
                    let r = DraughtsAI.bestMove(in: g, difficulty: .hard, rng: aiRng)
                    try? g.play(r.move!)
                } else {
                    let ms = g.legalMoves()
                    try? g.play(ms[Int(rnd.next() % UInt64(ms.count))])
                }
                XCTAssertLessThan(g.ply, 400)
            }
            XCTAssertEqual(g.score(for: 0), 1.0, "AI(白) 应战胜随机对手，seed=\(seed)")
        }
    }
}

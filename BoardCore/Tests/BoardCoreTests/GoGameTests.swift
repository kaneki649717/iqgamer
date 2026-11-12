import XCTest
@testable import BoardCore

final class GoGameTests: XCTestCase {

    // MARK: - 基础规则

    func testInitialState() {
        let g = GoGame()
        XCTAssertEqual(g.boardSize, 9)
        XCTAssertEqual(g.currentPlayer, 0)
        XCTAssertEqual(g.ply, 0)
        XCTAssertEqual(g.board.count, 81)
        XCTAssertEqual(g.koPoint, -1)
        XCTAssertTrue(g.evaluate().isFinite)
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 82) // 81 空点 + 虚着
        XCTAssertTrue(moves.contains(.pass))
    }

    func testBoardSizes() {
        for s in GoGame.supportedSizes {
            let g = GoGame(boardSize: s)
            XCTAssertEqual(g.board.count, s * s)
            XCTAssertEqual(g.legalMoves().count, s * s + 1)
        }
    }

    /// 提子：打吃后提一子，子数正确
    func testCaptureSingleStone() throws {
        var g = GoGame()
        try g.play(GoGame.GoMove(point: 20)) // 黑 (2,2)
        try g.play(GoGame.GoMove(point: 0))  // 白 (0,0)
        try g.play(GoGame.GoMove(point: 1))  // 黑 (0,1) 打吃，白 (0,0) 仅剩 (1,0) 一气
        try g.play(GoGame.GoMove(point: 40)) // 白 (4,4)
        try g.play(GoGame.GoMove(point: 9))  // 黑 (1,0) 提掉白 (0,0)
        XCTAssertEqual(g.board[0], 0)
        XCTAssertEqual(g.board.filter { $0 == 1 }.count, 3)
        XCTAssertEqual(g.board.filter { $0 == 2 }.count, 1)
        XCTAssertEqual(g.koPoint, -1) // 提子后黑 (1,0) 尚有两气，不构成劫
    }

    /// 禁自杀：填入自己最后一口气的点不在合法着法中
    func testSuicideIllegal() throws {
        var g = GoGame()
        // 白四子围住 (2,2)，黑填入为自杀（不提任何白子）
        let seq: [UInt16] = [0, 11, 1, 19, 2, 21, 3, 29]
        for p in seq { try g.play(GoGame.GoMove(point: p)) }
        let points = Set(g.legalMoves().map { Int($0.point) })
        XCTAssertFalse(points.contains(20))
        XCTAssertThrowsError(try g.play(GoGame.GoMove(point: 20)))
    }

    /// 若同时提敌则「看似自杀」的点合法
    func testCaptureAllowedWhereOtherwiseSuicide() throws {
        var g = GoGame()
        // 白 (0,0)(1,0) 仅剩最后一口气 (2,0)；黑 (2,0) 三面被围但能提子 → 合法
        let seq: [UInt16] = [1, 0, 10, 9, 65535, 19, 65535, 27]
        for p in seq { try g.play(GoGame.GoMove(point: p)) }
        let points = Set(g.legalMoves().map { Int($0.point) })
        XCTAssertTrue(points.contains(18))
        try g.play(GoGame.GoMove(point: 18))
        XCTAssertEqual(g.board[0], 0)
        XCTAssertEqual(g.board[9], 0)
        XCTAssertEqual(g.board.filter { $0 == 1 }.count, 3)
        XCTAssertEqual(g.board.filter { $0 == 2 }.count, 2)
    }

    /// 禁着点：占位点非法
    func testOccupiedPointIllegal() throws {
        var g = GoGame()
        try g.play(GoGame.GoMove(point: 20))
        XCTAssertThrowsError(try g.play(GoGame.GoMove(point: 20)))
        XCTAssertThrowsError(try g.play(GoGame.GoMove(point: 81))) // 越界
        XCTAssertFalse(g.legalMoves().map { Int($0.point) }.contains(20))
    }

    /// 劫：单劫局面下立即回提非法；隔一手后可回提并形成新的劫禁点
    func testSimpleKoForbidden() throws {
        var g = GoGame()
        // 经典单劫：黑 (2,3)(3,2)(4,3)，白 (2,4)(3,5)(4,4)；
        // 黑 (3,4) 提白 (3,3)，白 (3,3) 又提黑 (3,4) → 黑不得立即回提
        let seq: [UInt16] = [21, 22, 29, 32, 39, 40, 31, 30]
        for p in seq { try g.play(GoGame.GoMove(point: p)) }
        XCTAssertEqual(g.koPoint, 31)
        var points = Set(g.legalMoves().map { Int($0.point) })
        XCTAssertFalse(points.contains(31))
        XCTAssertThrowsError(try g.play(GoGame.GoMove(point: 31)))
        // 黑找一手棋（劫材位）、白应一手后，黑即可回提并形成新的劫禁点
        try g.play(GoGame.GoMove(point: 50)) // 黑 (5,5)
        try g.play(GoGame.GoMove(point: 45)) // 白 (5,0)
        points = Set(g.legalMoves().map { Int($0.point) })
        XCTAssertTrue(points.contains(31))
        try g.play(GoGame.GoMove(point: 31))
        XCTAssertEqual(g.board[30], 0)
        XCTAssertEqual(g.koPoint, 30)
        let whitePoints = Set(g.legalMoves().map { Int($0.point) })
        XCTAssertFalse(whitePoints.contains(30))
    }

    /// 双 pass 终局与数子：黑占大半盘（留两只真眼保证判活），白棋明显死棋
    func testDoublePassScoring() throws {
        var g = GoGame()
        // 黑占左半盘 cols 0..3；白 (2,2)(2,3) 被围仅剩 (2,4) 一口气，明显死棋
        // 黑特意留下 (4,1)(6,1) 两只真眼，否则黑大群会被死子启发误判
        try g.play(GoGame.GoMove(point: 0))  // 黑 (0,0)
        try g.play(GoGame.GoMove(point: 20)) // 白 (2,2)
        try g.play(GoGame.GoMove(point: 9))  // 黑 (1,0)
        try g.play(GoGame.GoMove(point: 21)) // 白 (2,3)
        var blackPoints: [UInt16] = []
        for r in 0..<9 {
            for c in 0..<4 {
                let p = r * 9 + c
                if p == 0 || p == 9 || p == 20 || p == 21 || p == 37 || p == 55 { continue }
                blackPoints.append(UInt16(p))
            }
        }
        for p in blackPoints {
            try g.play(GoGame.GoMove(point: p))
            try g.play(.pass) // 白虚着
        }
        try g.play(.pass) // 黑虚着，与白上一手连成双虚着 → 终局
        XCTAssertTrue(g.isOver)
        XCTAssertThrowsError(try g.play(.pass)) // 终局后再落子报错
        let score = g.computeAreaScore()
        XCTAssertEqual(score.white, 0.0)  // 白群无两真眼 → 判死移除
        XCTAssertEqual(score.black, 81.0) // 黑 32 活子 + 49 独占空点（含两只真眼位）
        XCTAssertGreaterThan(score.black, score.white + 7.5)
        XCTAssertEqual(g.score(for: 0), 1.0)
        XCTAssertEqual(g.score(for: 1), 0.0)
    }

    /// 死子启发：1 真眼白群判死；2 真眼黑群判活
    func testDeadGroupHeuristic() throws {
        var g = GoGame()
        // 白：左上一圈棋围住 (1,1) 一只真眼（仅 1 眼 → 判死）
        // 黑：右下一块带两只真眼 (7,1)(7,4) 的大群（判活）
        let pairs: [(Int, Int)] = [
            (72, 0), (73, 1), (74, 2), (75, 9), (76, 11), (77, 18), (78, 19), (79, 20)
        ]
        for (b, w) in pairs {
            try g.play(GoGame.GoMove(point: UInt16(b)))
            try g.play(GoGame.GoMove(point: UInt16(w)))
        }
        for p in [80, 63, 65, 66, 68, 54, 55, 58, 59] {
            try g.play(GoGame.GoMove(point: UInt16(p)))
            try g.play(.pass)
        }
        let score = g.computeAreaScore()
        XCTAssertEqual(score.white, 0.0)  // 白群 1 真眼 → 判死移除
        XCTAssertEqual(score.black, 81.0) // 黑群 2 真眼 → 判活：17 子 + 64 独占空点
        XCTAssertGreaterThan(score.black, score.white + 7.5)
    }

    /// zobrist 一致性：同序列重放 key 相同
    func testZobristReplayConsistency() throws {
        var rng = SplitMix64(seed: 20240)
        var g1 = GoGame()
        var played: [GoGame.GoMove] = []
        for _ in 0..<60 {
            if g1.isOver { break }
            let ms = g1.legalMoves()
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try g1.play(m)
            played.append(m)
        }
        XCTAssertGreaterThan(played.count, 10)
        var g2 = GoGame()
        for m in played { try g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey)
        // 不同局面 key 应不同
        var g3 = GoGame()
        try g3.play(GoGame.GoMove(point: 40))
        XCTAssertNotEqual(GoGame().zobristKey, g3.zobristKey)
    }

    // MARK: - MCTS / AI

    /// 9 路开局 AI 首着落点应在距边 ≥2 的区域（星位 / 小目一带）
    func testAIFirstMovePrefersCenterArea() {
        let g = GoGame()
        let r = GoAI.bestMove(in: g, difficulty: .hard, rng: SplitMix64(seed: 12345))
        guard let m = r.move else {
            XCTFail("AI 未返回着法")
            return
        }
        XCTAssertNotEqual(m, .pass)
        let p = Int(m.point)
        let row = p / 9
        let col = p % 9
        let edgeDist = min(min(row, 8 - row), min(col, 8 - col))
        XCTAssertGreaterThanOrEqual(edgeDist, 2, "首着应在距边 ≥2 的位置，实际 (\(row), \(col))")
    }

    /// AI（黑）对纯随机对手 3 局全胜
    func testAIBeatsRandomOpponent() throws {
        for seed in [11, 22, 33] {
            var g = GoGame()
            var aiRng = SplitMix64(seed: 99)
            var rnd = SplitMix64(seed: UInt64(seed))
            var safety = 0
            while !g.isOver {
                safety += 1
                if safety > 400 {
                    XCTFail("对局 400 手仍未结束")
                    break
                }
                if g.currentPlayer == 0 {
                    let r = GoAI.bestMove(in: g, difficulty: .medium, rng: aiRng)
                    guard let m = r.move else {
                        XCTFail("AI 未返回着法")
                        break
                    }
                    try g.play(m)
                } else {
                    let ms = g.legalMoves()
                    if ms.isEmpty { break }
                    try g.play(ms[Int(rnd.next() % UInt64(ms.count))])
                }
            }
            XCTAssertEqual(g.score(for: 0), 1.0, "AI(黑) 应战胜随机对手，seed=\(seed)")
        }
    }

    /// 天人档 9 路单步耗时 <8s（宽松上限，CI 机器慢）
    func testCelestialMoveWithinTimeBudget() {
        let g = GoGame()
        let start = Date()
        let r = GoAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 777))
        let elapsed = Date().timeIntervalSince(start)
        guard let m = r.move else {
            XCTFail("AI 未返回着法")
            return
        }
        XCTAssertNotEqual(m, .pass)
        XCTAssertTrue(g.legalMoves().contains(m))
        XCTAssertLessThan(elapsed, 8.0, "天人档 9 路单步应 <8s，实际 \(elapsed)s")
    }
}

import XCTest
@testable import BoardCore

final class GomokuTests: XCTestCase {

    private func m(_ r: Int, _ c: Int) -> Gomoku.GomokuMove { Gomoku.GomokuMove(row: r, col: c) }

    func testFirstMoveIsCenter() {
        let g = Gomoku()
        XCTAssertEqual(g.legalMoves(), [m(7, 7)])
    }

    func testWinInRow() {
        var g = Gomoku()
        // 黑连五 (7,3)...(7,7)，白散走
        let whites = [m(0, 0), m(1, 1), m(2, 2), m(3, 3)]
        var wi = 0
        for col in 3...7 {
            try? g.play(m(7, col))
            if col != 7, wi < whites.count { try? g.play(whites[wi]); wi += 1 }
        }
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.winner, 0)
        XCTAssertEqual(g.score(for: 0), 1.0)
    }

    func testOverlineWins() {
        var g = Gomoku()
        let whites = [m(0, 0), m(1, 1), m(2, 2), m(3, 3), m(4, 4)]
        var wi = 0
        // 黑六连也算胜（自由规则）
        for col in 3...8 {
            try? g.play(m(7, col))
            if col != 8, wi < whites.count { try? g.play(whites[wi]); wi += 1 }
        }
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.winner, 0)
    }

    func testAICapturesWinningMove() {
        // 黑（AI）已有活四 (7,3)-(7,6)，两端开放 → 任一端连五即胜
        var g = Gomoku()
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(7, 3), m(8, 3)),
            (m(7, 4), m(8, 4)),
            (m(7, 5), m(8, 5)),
            (m(7, 6), m(8, 6)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        let r = GomokuAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 2))
        XCTAssertTrue(r.move == m(7, 2) || r.move == m(7, 7), "AI 应连五，实际 \(String(describing: r.move))")
        var after = g
        try? after.play(r.move!)
        XCTAssertTrue(after.isOver)
        XCTAssertEqual(after.winner, 0)
    }

    func testAIBlocksFour() {
        // 白已有冲四 (8,3)-(8,6)，(8,2) 被黑占 → 唯一成五点 (8,7)，黑必须堵
        var g = Gomoku()
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(0, 0), m(8, 3)),
            (m(0, 1), m(8, 4)),
            (m(0, 2), m(8, 5)),
            (m(8, 2), m(8, 6)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        let r = GomokuAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 3))
        XCTAssertEqual(r.move, m(8, 7), "AI 必须堵白的唯一成五点，实际 \(String(describing: r.move))")
    }

    /// 回归测试：评估必须看见下半区威胁（旧实现每条线只扫线头窗口 → 下半区全盲）
    func testEvaluateSeesLowerHalfThreats() {
        var g = Gomoku()
        // 黑在下半区纵向连三 (10,10)(11,10)(12,10)，两端 (9,10)(13,10) 空
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(10, 10), m(0, 0)),
            (m(11, 10), m(1, 0)),
            (m(12, 10), m(2, 14)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        // 6 手后轮黑走，黑有活三 → 黑视角评估必须显著为正
        XCTAssertGreaterThan(g.evaluate(), 15,
                             "下半区黑活三必须被评估看见（盲区回归），当前 \(g.evaluate())")
    }

    /// 回归测试：AI 必须堵住下半区的纵向冲四
    func testAIBlocksVerticalFourLowerHalf() {
        var g = Gomoku()
        // 黑子散落在顶区（无威胁）；白在下半区纵向四连 (8,7)-(11,7)
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(0, 0),  m(8, 7)),
            (m(0, 3),  m(9, 7)),
            (m(0, 6),  m(10, 7)),
            (m(0, 9),  m(11, 7)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        // 白冲四两端 (7,7)(12,7) 均空 → 黑必堵其一（虽然活四已无解，但堵是唯一合理着法）
        let r = GomokuAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 9))
        XCTAssertTrue(r.move == m(7, 7) || r.move == m(12, 7),
                      "AI 必须堵下半区纵向冲四，实际 \(String(describing: r.move))")
    }

    /// VCF：黑活三 → 首着应为成活四点（两端任一）
    func testVCFFindsOpenFourWin() {
        var g = Gomoku()
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(7, 5), m(0, 0)),
            (m(7, 6), m(0, 3)),
            (m(7, 7), m(0, 6)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        let first = g.vcfFirstMove(player: 0)
        XCTAssertTrue(first == 7 * 15 + 4 || first == 7 * 15 + 8,
                      "VCF 应找到成活四点，实际 \(String(describing: first))")
    }

    /// VCF：安静局面不得误报
    func testVCFNoFalsePositiveQuiet() {
        var g = Gomoku()
        try? g.play(m(0, 0)); try? g.play(m(14, 14))
        try? g.play(m(0, 4)); try? g.play(m(14, 10))
        XCTAssertNil(g.vcfFirstMove(player: 0), "无四可冲的安静局面不应误报 VCF")
    }

    /// bestMove 集成：黑活三 → 直接下成活四点
    func testBestMovePlaysVCFFour() {
        var g = Gomoku()
        let seq: [(Gomoku.GomokuMove, Gomoku.GomokuMove)] = [
            (m(7, 5), m(0, 0)),
            (m(7, 6), m(0, 3)),
            (m(7, 7), m(0, 6)),
        ]
        for (b, w) in seq { try? g.play(b); try? g.play(w) }
        let r = GomokuAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 2))
        XCTAssertTrue(r.move == m(7, 4) || r.move == m(7, 8),
                      "bestMove 应执行 VCF 成活四着法，实际 \(String(describing: r.move))")
    }

    func testZobristReplay() {
        var g1 = Gomoku()
        var rng = SplitMix64(seed: 88)
        var seq: [Gomoku.GomokuMove] = []
        for _ in 0..<20 {
            let ms = g1.legalMoves()
            if g1.isOver { break }
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try? g1.play(m)
            seq.append(m)
        }
        var g2 = Gomoku()
        for m in seq { try? g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey)
    }

    func testAIBeatsRandom() {
        for seed in [5, 6] {
            var g = Gomoku()
            var rnd = SplitMix64(seed: UInt64(seed))
            var plies = 0
            while !g.isOver && plies < 225 {
                if g.currentPlayer == 0 {
                    let r = GomokuAI.bestMove(in: g, difficulty: .medium, rng: SplitMix64(seed: UInt64(plies) + 10))
                    if let m = r.move { try? g.play(m) } else { break }
                } else {
                    let ms = g.legalMoves()
                    try? g.play(ms[Int(rnd.next() % UInt64(ms.count))])
                }
                plies += 1
            }
            XCTAssertEqual(g.winner, 0, "五子棋 hard AI 应战胜随机对手，plies=\(plies)")
        }
    }

    func testIllegalOnOccupied() {
        var g = Gomoku()
        try? g.play(m(7, 7))
        XCTAssertThrowsError(try g.play(m(7, 7)))
    }
}

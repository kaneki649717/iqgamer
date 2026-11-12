import XCTest
@testable import BoardCore

final class ChessTests: XCTestCase {

    private func sq(_ r: Int, _ c: Int) -> UInt8 { UInt8(r * 8 + c) }

    func testInitialLegalMoves20() {
        let g = Chess()
        XCTAssertEqual(g.legalMoves().count, 20)
        XCTAssertEqual(g.currentPlayer, 0)
    }

    func testPerftStartPos() {
        XCTAssertEqual(perft(Chess(), 1), 20)
        XCTAssertEqual(perft(Chess(), 2), 400)
        XCTAssertEqual(perft(Chess(), 3), 8902)
    }

    private func perft(_ g: Chess, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var total = 0
        for m in g.legalMoves() {
            var c = g
            try? c.play(m)
            total += depth == 1 ? 1 : perft(c, depth - 1)
        }
        return total
    }

    func testCastling() {
        var g = Chess()
        // 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O
        let seq: [Chess.ChessMove] = [
            .init(from: 52, to: 36), // e2-e4
            .init(from: 12, to: 20), // e7-e5
            .init(from: 62, to: 45), // Ng1-f3
            .init(from: 1,  to: 18), // Nb8-c6
            .init(from: 61, to: 34), // Bf1-c4
            .init(from: 5,  to: 26), // Bf8-c5
        ]
        for m in seq { try? g.play(m) }
        XCTAssertTrue(g.legalMoves().contains(.init(from: 60, to: 62)), "白应可王侧易位")
        try? g.play(.init(from: 60, to: 62)) // O-O
        XCTAssertEqual(g.board[62], 6)   // 白王到 g1
        XCTAssertEqual(g.board[61], 4)   // 白车到 f1
        XCTAssertEqual(g.castling & 0b0011, 0)
        XCTAssertEqual(g.kingSq.0, 62)
    }

    func testCastlingRightLostByRookCapture() {
        // 黑象吃掉 a1 车 → 白后侧易位权消失
        var b = Array(repeating: UInt8(0), count: 64)
        b[60] = 6      // 白王 e1
        b[56] = 4      // 白车 a1
        b[4] = 0b1110  // 黑王 e8
        b[49] = 0b1011 // 黑象 b2
        var g = Chess(board: b, player: 1, castling: 0b0011)
        let m = Chess.ChessMove(from: 49, to: 56) // 象沿对角吃 a1 车
        XCTAssertTrue(g.legalMoves().contains(m))
        try? g.play(m)
        XCTAssertEqual(g.castling & 0b0010, 0, "白后侧易位权应被取消")
        XCTAssertEqual(g.castling & 0b0001, 1, "白王侧权利保留")
    }

    func testEnPassant() {
        var g = Chess()
        try? g.play(.init(from: 52, to: 36)) // e4
        try? g.play(.init(from: 8, to: 16)) // a6
        try? g.play(.init(from: 36, to: 28)) // e5
        try? g.play(.init(from: 11, to: 27)) // d7-d5（双步）
        XCTAssertTrue(g.legalMoves().contains(.init(from: 28, to: 19)), "白兵应可吃过路兵 d6")
        try? g.play(.init(from: 28, to: 19)) // exd6
        XCTAssertEqual(g.board[27], 0, "被吃过路兵应消失")
        XCTAssertEqual(g.board[19], 1)
    }

    func testPromotionGeneratesFourMoves() {
        var b = Array(repeating: UInt8(0), count: 64)
        b[15] = 1          // 白兵 h7（row1 col7）
        b[60] = 6          // 白王 e1
        b[4] = 0b1110      // 黑王 e8
        let g = Chess(board: b, player: 0)
        let promos = g.legalMoves().filter { $0.from == 15 && $0.to == 7 }
        XCTAssertEqual(promos.count, 4)
        XCTAssertEqual(Set(promos.compactMap(\.promotion)), Set([0, 1, 2, 3] as Set<UInt8>))
    }

    func testFoolsMate() {
        var g = Chess()
        try? g.play(.init(from: 53, to: 45)) // f3
        try? g.play(.init(from: 12, to: 20)) // e5
        try? g.play(.init(from: 54, to: 38)) // g4
        try? g.play(.init(from: 3, to: 39))  // Qh4#
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 0), 0.0)
        XCTAssertEqual(g.score(for: 1), 1.0)
    }

    func testMatedPositionDetection() {
        // 黑王 h8，白王 f6，白后 g7（受王保护）：黑被将死
        var b = Array(repeating: UInt8(0), count: 64)
        b[7] = 0b1110
        b[21] = 6
        b[14] = 5
        let g = Chess(board: b, player: 1)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 1), 0.0)
        XCTAssertEqual(g.score(for: 0), 1.0)
    }

    func testAIFindsMateInOne() {
        // 白后 h2，白王 g6，黑王 h8：一手杀（Qh7# / Qg7# 类）
        var b = Array(repeating: UInt8(0), count: 64)
        b[7] = 0b1110
        b[22] = 6
        b[55] = 5
        let g = Chess(board: b, player: 0)
        let r = ChessAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 5))
        XCTAssertNotNil(r.move)
        var after = g
        try? after.play(r.move!)
        XCTAssertTrue(after.isOver, "AI 应找到一手杀，实际走了 \(String(describing: r.move))")
        XCTAssertEqual(after.score(for: 0), 1.0)
    }

    func testInsufficientMaterial() {
        var b = Array(repeating: UInt8(0), count: 64)
        b[60] = 6; b[4] = 0b1110
        let g = Chess(board: b, player: 0)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 0), 0.5)
    }

    func testStalemate() {
        // 黑王 a8，白后 c7，白王 b6：黑无着且不被将 → 逼和
        var b = Array(repeating: UInt8(0), count: 64)
        b[0] = 0b1110
        b[10] = 5
        b[17] = 6
        let g = Chess(board: b, player: 1)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.score(for: 1), 0.5)
    }

    func testZobristReplay() {
        var g1 = Chess()
        var rng = SplitMix64(seed: 77)
        var seq: [Chess.ChessMove] = []
        for _ in 0..<24 {
            let ms = g1.legalMoves()
            if g1.isOver { break }
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try? g1.play(m)
            seq.append(m)
        }
        var g2 = Chess()
        for m in seq { try? g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey)
        XCTAssertEqual(g1.castling, g2.castling)
        XCTAssertEqual(g1.epSquare, g2.epSquare)
    }

    func testAIBeatRandomKQK() {
        var b = Array(repeating: UInt8(0), count: 64)
        b[4] = 0b1110  // 黑王 e8
        b[28] = 6      // 白王 e4
        b[35] = 5      // 白后 d5
        var g = Chess(board: b, player: 0)
        var rng = SplitMix64(seed: 3)
        var plies = 0
        while !g.isOver && plies < 80 {
            if g.currentPlayer == 0 {
                let r = ChessAI.bestMove(in: g, difficulty: .hard, rng: SplitMix64(seed: UInt64(plies) + 100))
                if let m = r.move { try? g.play(m) } else { break }
            } else {
                let ms = g.legalMoves()
                if ms.isEmpty { break }
                try? g.play(ms[Int(rng.next() % UInt64(ms.count))])
            }
            plies += 1
        }
        XCTAssertEqual(g.score(for: 0), 1.0, "KQK 白棋 \(plies) 步内应取胜")
        XCTAssertLessThan(plies, 80)
    }
}

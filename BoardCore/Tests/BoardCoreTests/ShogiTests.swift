import XCTest
@testable import BoardCore

final class ShogiTests: XCTestCase {

    private func sq(_ r: Int, _ c: Int) -> UInt8 { UInt8(r * 9 + c) }

    func testInitialLegalMoves30() {
        let g = Shogi()
        XCTAssertEqual(g.legalMoves().count, 30, "平手初形先手合法手应为 30（歩9 香2 銀4 金6 玉3 飛6）")
        // 桂与角开局动不了
        XCTAssertFalse(g.legalMoves().contains { m in
            guard let f = m.from else { return false }
            return Shogi.typeOf(g.board[Int(f)]) == 6 || Shogi.typeOf(g.board[Int(f)]) == 3
        })
    }

    func testInitialSetup() {
        let g = Shogi()
        XCTAssertEqual(Shogi.typeOf(g.board[70]), 2)          // 先手飛 2八
        XCTAssertEqual(Shogi.colorOf(g.board[70]), 0)
        XCTAssertEqual(Shogi.typeOf(g.board[64]), 3)          // 先手角 8八
        XCTAssertEqual(Shogi.typeOf(g.board[10]), 2)          // 后手飛 8二
        XCTAssertEqual(Shogi.colorOf(g.board[10]), 1)
        XCTAssertEqual(Shogi.typeOf(g.board[16]), 3)          // 后手角 2二
        XCTAssertEqual(Shogi.typeOf(g.board[76]), 1)          // 先手王 5九
        XCTAssertEqual(Shogi.typeOf(g.board[4]), 1)           // 后手王 5一
    }

    func testKnightJumpOverBlocker() {
        // 桂是跳子：目标格空即可落，中间是否有子无关
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1                                  // 先手王 5九
        b[4] = 0b100000 | 1                        // 后手王 5一
        b[73] = 6                                  // 先手桂 8九
        b[65] = 8                                  // 先手歩 (7,2)（在桂的斜邻，不影响跳跃）
        let g = Shogi(board: b, hand: [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]], player: 0)
        let targets = g.legalMoves().filter { $0.from == 73 }.map { Int($0.to) }
        XCTAssertEqual(Set(targets), Set([54, 56]))  // (6,0)=54, (6,2)=56
    }

    func testForcedPromotion() {
        // 先手歩从 (1,4) 进到 (0,4)：只生成升变
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1; b[4] = 0b100000 | 1
        b[13] = 8                                  // 先手歩 (1,4)
        let g = Shogi(board: b, hand: [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]], player: 0)
        let promos = g.legalMoves().filter { $0.from == 13 && $0.to == 4 }
        XCTAssertEqual(promos.count, 1)
        XCTAssertTrue(promos[0].promote)
    }

    func testOptionalPromotion() {
        // 先手銀从 (3,4) 进到 (2,4)：进入敌阵，升变/不升变两种
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1; b[4] = 0b100000 | 1
        b[31] = 5                                  // 先手銀 (3,4)
        let g = Shogi(board: b, hand: [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]], player: 0)
        let ms = g.legalMoves().filter { $0.from == 31 && $0.to == 22 }
        XCTAssertEqual(ms.count, 2)
        XCTAssertEqual(ms.filter(\.promote).count, 1)
    }

    func testNifu() {
        // 同列（col 3）已有先手未成歩 → 打歩非法
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1; b[4] = 0b100000 | 1
        b[57] = 8                                  // 先手歩 (6,3)
        var hand = [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]]
        hand[0][8] = 1
        let g = Shogi(board: b, hand: hand, player: 0)
        XCTAssertFalse(g.legalMoves().contains { $0.drop == 8 && Shogi.rc(Int($0.to)).1 == 3 },
                       "同列有歩时禁二歩")
        XCTAssertTrue(g.legalMoves().contains { $0.drop == 8 && Shogi.rc(Int($0.to)).1 == 4 },
                      "其他列打歩合法")
    }

    func testDropBasics() {
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1; b[4] = 0b100000 | 1
        var hand = [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]]
        hand[0][4] = 1 // 先手持金
        let g = Shogi(board: b, hand: hand, player: 0)
        XCTAssertTrue(g.legalMoves().contains(Shogi.ShogiMove(from: nil, to: 40, drop: 4)))
        // 占用格不可打
        XCTAssertFalse(g.legalMoves().contains(Shogi.ShogiMove(from: nil, to: 76, drop: 4)))
    }

    func testUchifuzumeIllegal() {
        // 后手王 (0,0)，后手桂 (0,1)，后手銀 (1,1)；
        // 先手金 (2,0)，手持歩。打歩 (1,0) 直接将死 → 非法（打歩诘）
        var b = Array(repeating: UInt8(0), count: 81)
        b[0] = 0b100000 | 1                        // 后手王 (0,0)
        b[1] = 0b100000 | 6                        // 后手桂 (0,1)
        b[10] = 0b100000 | 5                       // 后手銀 (1,1)
        b[18] = 4                                  // 先手金 (2,0)
        b[76] = 1                                  // 先手王 5九
        var hand = [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]]
        hand[0][8] = 1
        let g = Shogi(board: b, hand: hand, player: 0)
        let pawnDropMate = Shogi.ShogiMove(from: nil, to: 9, drop: 8) // (1,0)
        XCTAssertFalse(g.legalMoves().contains(pawnDropMate), "打歩诘必须被禁止")
        // 验证该打歩确实构成将死（用 force 重放验证逻辑）：直接落子后对方无合法着法
        var probe = g
        probe.forcePlay(pawnDropMate)
        XCTAssertEqual(probe.legalMoves().count, 0)
        XCTAssertEqual(probe.isInCheck, true)
    }

    func testCaptureGoesToHand() {
        // 先手飛 (5,4) 沿线吃后手歩 (3,4)，吃的歩应进手驹
        var b = Array(repeating: UInt8(0), count: 81)
        b[76] = 1
        b[4] = 0b100000 | 1
        b[49] = 2                                  // 先手飛 (5,4)
        b[31] = 0b100000 | 8                       // 后手歩 (3,4)
        let g = Shogi(board: b, hand: [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]], player: 0)
        XCTAssertTrue(g.legalMoves().contains(Shogi.ShogiMove(from: 49, to: 31)))
        var after = g
        try? after.play(Shogi.ShogiMove(from: 49, to: 31))
        XCTAssertEqual(after.hand[0][8], 1, "吃的歩应进手驹")
        XCTAssertEqual(after.board[31], 2)
        XCTAssertEqual(after.board[49], 0)
    }

    func testZobristReplay() {
        var g1 = Shogi()
        var rng = SplitMix64(seed: 123)
        var seq: [Shogi.ShogiMove] = []
        for _ in 0..<40 {
            let ms = g1.legalMoves()
            if g1.isOver { break }
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try? g1.play(m)
            seq.append(m)
        }
        var g2 = Shogi()
        for m in seq { try? g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey)
        XCTAssertEqual(g1.hand, g2.hand)
    }

    func testAIVsRandomStable() {
        var g = Shogi()
        var rnd = SplitMix64(seed: 9)
        var plies = 0
        while !g.isOver && plies < 40 {
            if g.currentPlayer == 0 {
                let r = ShogiAI.bestMove(in: g, difficulty: .easy, rng: SplitMix64(seed: UInt64(plies) + 1))
                if let m = r.move { try? g.play(m) } else { break }
            } else {
                let ms = g.legalMoves()
                if ms.isEmpty { break }
                try? g.play(ms[Int(rnd.next() % UInt64(ms.count))])
            }
            plies += 1
        }
        XCTAssertGreaterThan(plies, 5, "对局应正常进行")
    }

    func testMatedPositionDetection() {
        // 后手王 (0,4) 被先手飛 (3,4) 直线将死：
        // (0,3)(0,5) 被金 (1,3)(1,5) 控制；(1,3)(1,5) 被銀 (2,3)(2,5) 保护；(1,4) 在飛线上；无子可挡
        var b = Array(repeating: UInt8(0), count: 81)
        b[4] = 0b100000 | 1   // 后手王 (0,4)
        b[76] = 1             // 先手王 5九
        b[12] = 4             // 先手金 (1,3)
        b[14] = 4             // 先手金 (1,5)
        b[21] = 5             // 先手銀 (2,3)
        b[23] = 5             // 先手銀 (2,5)
        b[31] = 2             // 先手飛 (3,4)
        let g = Shogi(board: b, hand: [[0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0]], player: 1)
        XCTAssertTrue(g.isOver, "后手应被将死")
        XCTAssertEqual(g.score(for: 1), 0.0)
        XCTAssertEqual(g.score(for: 0), 1.0)
    }
}

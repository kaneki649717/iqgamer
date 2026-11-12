import XCTest
@testable import BoardCore

final class XiangqiTests: XCTestCase {

    /// 棋子编码：低 3 位类型 1帥 2仕 3相 4馬 5車 6炮 7兵；bit3 = 黑方旗标
    private func pc(_ type: UInt8, _ black: Bool = false) -> UInt8 {
        black ? (0b1000 | type) : type
    }

    private func emptyBoard() -> [UInt8] {
        Array(repeating: UInt8(0), count: 90)
    }

    // MARK: - 起始局面

    func testInitialLegalMoves44() {
        let g = Xiangqi()
        XCTAssertEqual(g.currentPlayer, 0)
        XCTAssertEqual(g.ply, 0)
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 44, "开局合法着法应为 44")
        // 开局仅有的两个吃子：红炮隔黑炮打黑马（64→1、70→7）
        let captures = Set(moves.filter { g.board[Int($0.to)] != 0 })
        XCTAssertEqual(captures, Set([Xiangqi.XiangqiMove(from: 64, to: 1),
                                      Xiangqi.XiangqiMove(from: 70, to: 7)]))
        // 马腿：开局马不能横跳（相蹩腿）
        XCTAssertFalse(moves.contains(Xiangqi.XiangqiMove(from: 82, to: 75)))
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 82, to: 63)))
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 82, to: 65)))
        // 车、相、帥、兵抽查
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 81, to: 72)))
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 83, to: 67)))
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 85, to: 76)))
        XCTAssertTrue(moves.contains(Xiangqi.XiangqiMove(from: 54, to: 45)))
    }

    func testPerftStartPos() {
        // 基准值来自 Chess Programming Wiki《Chinese Chess Perft Results》
        XCTAssertEqual(perft(Xiangqi(), 1), 44)
        XCTAssertEqual(perft(Xiangqi(), 2), 1920)
        XCTAssertEqual(perft(Xiangqi(), 3), 79_666)
    }

    private func perft(_ g: Xiangqi, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var total = 0
        for m in g.legalMoves() {
            var c = g
            try? c.play(m)
            total += depth == 1 ? 1 : perft(c, depth - 1)
        }
        return total
    }

    // MARK: - 马腿

    func testHorseLeg() {
        // 红马 (5,4)，红兵 (4,4) 蹩住上跳马腿
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[5] = pc(1, true)   // 黑將 (0,5)
        b[49] = 4            // 红馬 (5,4)
        b[40] = 7            // 红兵 (4,4)——蹩腿子
        var g = Xiangqi(board: b, player: 0)
        var horseMoves = g.legalMoves().filter { $0.from == 49 }
        XCTAssertFalse(horseMoves.contains(.init(from: 49, to: 30)), "(3,3) 上跳被蹩")
        XCTAssertFalse(horseMoves.contains(.init(from: 49, to: 32)), "(3,5) 上跳被蹩")
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 66)))   // (7,3)
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 68)))   // (7,5)
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 38)))   // (4,2) 横跳腿(5,3)空
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 42)))   // (4,6)
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 56)))   // (6,2)
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 60)))   // (6,6)
        // 移开蹩腿子后上跳恢复
        b[40] = 0
        g = Xiangqi(board: b, player: 0)
        horseMoves = g.legalMoves().filter { $0.from == 49 }
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 30)))
        XCTAssertTrue(horseMoves.contains(.init(from: 49, to: 32)))
    }

    // MARK: - 相眼 / 过河

    func testElephantEyeAndRiver() {
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[5] = pc(1, true)   // 黑將 (0,5)
        b[49] = 3            // 红相 (5,4)
        var g = Xiangqi(board: b, player: 0)
        var moves = g.legalMoves().filter { $0.from == 49 }
        // 相不过河：(3,2)/(3,6) 非法；本方半场 (7,2)/(7,6) 合法
        XCTAssertEqual(Set(moves), Set([Xiangqi.XiangqiMove(from: 49, to: 65),
                                        Xiangqi.XiangqiMove(from: 49, to: 69)]))
        XCTAssertFalse(moves.contains(.init(from: 49, to: 29)))
        XCTAssertFalse(moves.contains(.init(from: 49, to: 33)))
        // 象眼 (6,3) 被塞 → (7,2) 不可达
        b[57] = 7
        g = Xiangqi(board: b, player: 0)
        moves = g.legalMoves().filter { $0.from == 49 }
        XCTAssertEqual(moves, [Xiangqi.XiangqiMove(from: 49, to: 69)])
    }

    // MARK: - 照面

    func testFlyingGeneralFacing() {
        // 双方将同列（e 列）无遮挡：所有不解除照面的走法非法
        var b = emptyBoard()
        b[85] = 1            // 红帥 (9,4)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[81] = 5            // 红車 (9,0)
        let g = Xiangqi(board: b, player: 0)
        let moves = g.legalMoves()
        XCTAssertEqual(Set(moves), Set([Xiangqi.XiangqiMove(from: 85, to: 84),
                                        Xiangqi.XiangqiMove(from: 85, to: 86)]),
                       "只有帥横移离开 e 列合法")
        XCTAssertFalse(moves.contains(.init(from: 85, to: 76)), "帥进 (8,4) 仍照面，非法")
        XCTAssertFalse(moves.contains(.init(from: 81, to: 72)), "車动不解除照面，非法")
    }

    func testFlyingGeneralBlock() {
        // 車垫入 e 列可解除照面
        var b = emptyBoard()
        b[85] = 1            // 红帥 (9,4)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[45] = 5            // 红車 (5,0)
        let g = Xiangqi(board: b, player: 0)
        let moves = g.legalMoves()
        XCTAssertEqual(moves.count, 3)
        XCTAssertTrue(moves.contains(.init(from: 45, to: 49)), "車(5,0)-(5,4) 垫将应合法")
        XCTAssertFalse(moves.contains(.init(from: 45, to: 44)), "(4,0) 不解除照面")
        XCTAssertFalse(moves.contains(.init(from: 45, to: 0)), "(0,0) 不解除照面")
        XCTAssertTrue(moves.contains(.init(from: 85, to: 84)))
        XCTAssertTrue(moves.contains(.init(from: 85, to: 86)))
    }

    // MARK: - 炮隔子

    func testCannonScreenCapture() {
        // 红炮 (5,4)、黑卒 (3,4) 作炮架、黑馬 (1,4) 为目标
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[5] = pc(1, true)   // 黑將 (0,5)
        b[49] = 6            // 红炮 (5,4)
        b[31] = pc(7, true)  // 黑卒 (3,4)——炮架
        b[13] = pc(4, true)  // 黑馬 (1,4)——目标
        var g = Xiangqi(board: b, player: 0)
        var moves = g.legalMoves().filter { $0.from == 49 }
        XCTAssertTrue(moves.contains(.init(from: 49, to: 13)), "有架子应能隔子吃马")
        XCTAssertTrue(moves.contains(.init(from: 49, to: 40)), "(4,4) 平移")
        XCTAssertFalse(moves.contains(.init(from: 49, to: 31)), "不能吃炮架本身")
        // 无炮架：不能隔空吃
        b[31] = 0
        g = Xiangqi(board: b, player: 0)
        moves = g.legalMoves().filter { $0.from == 49 }
        XCTAssertFalse(moves.contains(.init(from: 49, to: 13)), "无架子不能隔空吃")
        XCTAssertTrue(moves.contains(.init(from: 49, to: 22)), "(2,4) 平移至马前")
    }

    // MARK: - 兵

    func testPawnForwardAndSideways() {
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[5] = pc(1, true)   // 黑將 (0,5)
        b[40] = 7            // 红兵 (4,4)——已过河
        b[56] = 7            // 红兵 (6,2)——未过河
        let g = Xiangqi(board: b, player: 0)
        let moves = g.legalMoves()
        XCTAssertTrue(moves.contains(.init(from: 40, to: 31)), "(3,4) 前进")
        XCTAssertTrue(moves.contains(.init(from: 40, to: 39)), "(4,3) 过河可横移")
        XCTAssertTrue(moves.contains(.init(from: 40, to: 41)), "(4,5) 过河可横移")
        XCTAssertFalse(moves.contains(.init(from: 40, to: 49)), "兵不能后退")
        XCTAssertTrue(moves.contains(.init(from: 56, to: 47)), "(5,2) 前进")
        XCTAssertFalse(moves.contains(.init(from: 56, to: 55)), "未过河不能横移")
        XCTAssertFalse(moves.contains(.init(from: 56, to: 57)))
    }

    // MARK: - 一步杀（AI）

    func testAIFindsMateInOne() {
        // 红車 (1,1) 进 (1,4) 或 (0,1) 均成杀；双马控制黑将全部逃点
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[10] = 5            // 红車 (1,1)
        b[20] = 4            // 红馬 (2,2)：控 (0,3)、护 (1,4)
        b[24] = 4            // 红馬 (2,6)：控 (0,5)
        let g = Xiangqi(board: b, player: 0)
        XCTAssertTrue(g.legalMoves().contains(.init(from: 10, to: 13)))
        XCTAssertTrue(g.legalMoves().contains(.init(from: 10, to: 1)))
        let r = XiangqiAI.bestMove(in: g, difficulty: .celestial, rng: SplitMix64(seed: 5))
        guard let m = r.move else {
            XCTFail("AI 未返回着法")
            return
        }
        XCTAssertEqual(m.from, 10, "AI 应走車完成一步杀")
        var after = g
        try? after.play(m)
        XCTAssertTrue(after.isOver, "杀着之后对局应结束")
        XCTAssertEqual(after.score(for: 0), 1.0)
        XCTAssertEqual(after.score(for: 1), 0.0)
    }

    // MARK: - 无着法即负（将死）

    func testCheckmateScore() {
        // 黑被将死：車 (1,4) 将，马控逃点，黑无合法着法
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[13] = 5            // 红車 (1,4)
        b[20] = 4            // 红馬 (2,2)
        b[24] = 4            // 红馬 (2,6)
        let g = Xiangqi(board: b, player: 1)
        XCTAssertTrue(g.isOver)
        XCTAssertTrue(g.legalMoves().isEmpty)
        XCTAssertTrue(g.isInCheck)
        XCTAssertEqual(g.score(for: 1), 0.0, "被将死一方判负")
        XCTAssertEqual(g.score(for: 0), 1.0)
    }

    // MARK: - 和棋规则

    func testThreefoldRepetitionDraw() {
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[48] = 5            // 红車 (5,3)
        b[3] = pc(2, true)   // 黑士 (0,3)
        b[5] = pc(2, true)   // 黑士 (0,5)
        var g = Xiangqi(board: b, player: 0)
        let cycle: [Xiangqi.XiangqiMove] = [
            .init(from: 48, to: 47),  // 車 (5,3)-(5,2)
            .init(from: 3, to: 13),   // 士 (0,3)-(1,4)
            .init(from: 47, to: 48),
            .init(from: 13, to: 3),
        ]
        for m in cycle { try? g.play(m) }
        XCTAssertFalse(g.isOver, "重复两次不应终局")
        for m in cycle { try? g.play(m) }
        XCTAssertTrue(g.isOver, "三次重复局面应判和")
        XCTAssertEqual(g.score(for: 0), 0.5)
        XCTAssertEqual(g.score(for: 1), 0.5)
    }

    func testHalfmoveClockDraw() {
        var b = emptyBoard()
        b[84] = 1            // 红帥 (9,3)
        b[4] = pc(1, true)   // 黑將 (0,4)
        b[48] = 5            // 红車 (5,3)
        b[3] = pc(2, true)   // 黑士 (0,3)
        b[5] = pc(2, true)   // 黑士 (0,5)
        var g = Xiangqi(board: b, player: 0, halfmove: 119)
        XCTAssertFalse(g.isOver)
        try? g.play(.init(from: 48, to: 47))   // 非吃子着法
        XCTAssertEqual(g.halfmoveClock, 120)
        XCTAssertTrue(g.isOver, "120 半回合无吃子判和")
        XCTAssertEqual(g.score(for: 0), 0.5)
        XCTAssertEqual(g.score(for: 1), 0.5)
    }

    // MARK: - Zobrist

    func testZobristReplay() {
        var g1 = Xiangqi()
        var rng = SplitMix64(seed: 77)
        var seq: [Xiangqi.XiangqiMove] = []
        for _ in 0..<40 {
            let ms = g1.legalMoves()
            if g1.isOver { break }
            let m = ms[Int(rng.next() % UInt64(ms.count))]
            try? g1.play(m)
            seq.append(m)
        }
        XCTAssertFalse(seq.isEmpty)
        var g2 = Xiangqi()
        for m in seq { try? g2.play(m) }
        XCTAssertEqual(g1.zobristKey, g2.zobristKey, "同序列重放 key 应相同")
        XCTAssertEqual(g1.history, g2.history)
        XCTAssertEqual(g1.ply, g2.ply)
        // 增量维护应与全量重算一致
        XCTAssertEqual(g1.zobristKey, Xiangqi.computeKey(board: g1.board, player: g1.currentPlayer))
        XCTAssertEqual(g2.zobristKey, Xiangqi.computeKey(board: g2.board, player: g2.currentPlayer))
    }

    // MARK: - AI 对随机对手

    func testAIBeatsRandomWithExtraChariot() {
        for seed in [11, 22, 33] {
            var b = Xiangqi().board
            b[8] = 0   // 拿掉黑方一路車，红方多一车
            var g = Xiangqi(board: b, player: 0)
            var aiRng = SplitMix64(seed: 99)
            var rnd = SplitMix64(seed: UInt64(seed))
            var plies = 0
            while !g.isOver && plies < 160 {
                if g.currentPlayer == 0 {
                    let r = XiangqiAI.bestMove(in: g, difficulty: .hard, rng: aiRng)
                    guard let m = r.move else { break }
                    try? g.play(m)
                } else {
                    let ms = g.legalMoves()
                    guard !ms.isEmpty else { break }
                    try? g.play(ms[Int(rnd.next() % UInt64(ms.count))])
                }
                plies += 1
            }
            XCTAssertEqual(g.score(for: 0), 1.0,
                           "多一车的 AI 应战胜随机对手，seed=\(seed)，plies=\(plies)")
            XCTAssertLessThan(plies, 160)
        }
    }
}

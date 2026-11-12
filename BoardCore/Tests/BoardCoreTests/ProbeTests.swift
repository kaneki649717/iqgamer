import XCTest
@testable import BoardCore

final class ProbeTests: XCTestCase {
    func testProbeEP() {
        var g = Chess()
        let seq: [(UInt8, UInt8, String)] = [
            (52, 36, "e4"), (48, 40, "a6"), (36, 28, "e5"), (11, 27, "d5"),
        ]
        for (f, t, name) in seq {
            let res = try? g.play(Chess.ChessMove(from: f, to: t))
            print("PROBE \(name) \(f)→\(t) ok=\(res != nil ? "y" : "THREW") ep=\(g.epSquare) ply=\(g.ply)")
        }
        print("PROBE board[27]=\(g.board[27]) board[28]=\(g.board[28]) board[19]=\(g.board[19])")
        var pseudo: [Chess.ChessMove] = []
        g.appendPseudoMoves(to: &pseudo)
        print("PROBE pseudoWith19=\(pseudo.filter { $0.to == 19 }.count)")
        let legal = g.legalMoves()
        print("PROBE legalWith19=\(legal.filter { $0.to == 19 }.count) legalTotal=\(legal.count)")
    }
}

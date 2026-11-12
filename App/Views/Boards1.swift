import SwiftUI
import BoardCore

// MARK: - 围棋

struct GoBoardView: View {
    @ObservedObject var session: GameSession

    private var go: GoGame { session.go }
    private var n: Int { go.boardSize }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pad = side / (CGFloat(n) + 1)
            let cell = (side - pad * 2) / CGFloat(n - 1)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(BoardPalette.wood)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                Canvas { ctx, size in
                    let lineWidth = max(0.8, side / 400)
                    var path = Path()
                    for i in 0..<n {
                        let x = pad + CGFloat(i) * cell
                        path.move(to: CGPoint(x: x, y: pad))
                        path.addLine(to: CGPoint(x: x, y: side - pad))
                        path.move(to: CGPoint(x: pad, y: x))
                        path.addLine(to: CGPoint(x: side - pad, y: x))
                    }
                    ctx.stroke(path, with: .color(BoardPalette.gridLine), lineWidth: lineWidth)
                    // 星位
                    let stars = starPoints(n)
                    for (r, c) in stars {
                        let cx = pad + CGFloat(c) * cell
                        let cy = pad + CGFloat(r) * cell
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)),
                                 with: .color(BoardPalette.gridLine))
                    }
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    let x = pad + CGFloat(c) * cell
                    let y = pad + CGFloat(r) * cell
                    Group {
                        switch go.board[idx] {
                        case 1: StoneView(color: Color(white: 0.12))
                        case 2: StoneView(color: Color(white: 0.97))
                        default: Color.clear
                        }
                    }
                    .frame(width: cell * 0.94, height: cell * 0.94)
                    .position(x: x, y: y)
                }

                // 点击热区
                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: cell, height: cell)
                        .position(x: pad + CGFloat(c) * cell, y: pad + CGFloat(r) * cell)
                        .onTapGesture { tap(idx) }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if needPass {
                Button("我方只能停一手") { session.playGo(.pass) }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 16)
                    .glassButtonStyle()
                    .offset(y: 24)
            }
        }
    }

    private var humanTurn: Bool {
        session.currentPlayer == session.humanColor && !session.isOver && !session.aiThinking
    }

    private var needPass: Bool {
        humanTurn && go.legalMoves() == [.pass]
    }

    private func tap(_ idx: Int) {
        guard humanTurn else { return }
        session.playGo(GoGame.GoMove(idx))
    }

    private func starPoints(_ n: Int) -> [(Int, Int)] {
        if n == 9 { return [(2,2),(2,6),(6,2),(6,6),(4,4)] }
        if n == 13 { return [(3,3),(3,9),(9,3),(9,9),(6,6)] }
        return [(3,3),(3,9),(3,15),(9,3),(9,9),(9,15),(15,3),(15,9),(15,15)]
    }
}

// MARK: - 五子棋

struct GomokuBoardView: View {
    @ObservedObject var session: GameSession
    private let n = 15

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pad = side / (CGFloat(n) + 1)
            let cell = (side - pad * 2) / CGFloat(n - 1)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(BoardPalette.wood)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                Canvas { ctx, size in
                    var path = Path()
                    for i in 0..<n {
                        let x = pad + CGFloat(i) * cell
                        path.move(to: CGPoint(x: x, y: pad))
                        path.addLine(to: CGPoint(x: x, y: side - pad))
                        path.move(to: CGPoint(x: pad, y: x))
                        path.addLine(to: CGPoint(x: side - pad, y: x))
                    }
                    ctx.stroke(path, with: .color(BoardPalette.gridLine), lineWidth: max(0.8, side / 420))
                    // 天元
                    let cx = pad + 7 * cell, cy = pad + 7 * cell
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7)),
                             with: .color(BoardPalette.gridLine))
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    Group {
                        switch session.gomoku.board[idx] {
                        case 1: StoneView(color: Color(white: 0.12))
                        case 2: StoneView(color: Color(white: 0.97))
                        default: Color.clear
                        }
                    }
                    .frame(width: cell * 0.82, height: cell * 0.82)
                    .position(x: pad + CGFloat(c) * cell, y: pad + CGFloat(r) * cell)
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: cell, height: cell)
                        .position(x: pad + CGFloat(c) * cell, y: pad + CGFloat(r) * cell)
                        .onTapGesture { tap(idx) }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func tap(_ idx: Int) {
        guard session.currentPlayer == session.humanColor, !session.gomoku.isOver, !session.aiThinking else { return }
        session.playGomoku(Gomoku.GomokuMove(UInt8(idx)))
    }
}

// MARK: - 黑白棋

struct ReversiBoardView: View {
    @ObservedObject var session: GameSession
    private let n = 8

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(n)
            let legal: Set<UInt8> = {
                guard session.currentPlayer == session.humanColor, !session.isOver, !session.aiThinking else { return [] }
                return Set(session.reversi.legalMoves().map(\.square))
            }()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.42, blue: 0.22), Color(red: 0.07, green: 0.32, blue: 0.17)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                // 分格线
                Canvas { ctx, size in
                    var path = Path()
                    for i in 1..<n {
                        let v = CGFloat(i) * cell
                        path.move(to: CGPoint(x: v, y: 0)); path.addLine(to: CGPoint(x: v, y: size.height))
                        path.move(to: CGPoint(x: 0, y: v)); path.addLine(to: CGPoint(x: size.width, y: v))
                    }
                    ctx.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1)
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    let bit = UInt64(1) << idx
                    ZStack {
                        Group {
                            if session.reversi.black & bit != 0 {
                                StoneView(color: Color(white: 0.12))
                            } else if session.reversi.white & bit != 0 {
                                StoneView(color: Color(white: 0.97))
                            } else if legal.contains(UInt8(idx)) {
                                Circle()
                                    .strokeBorder(Color.qiAccent.opacity(0.7), lineWidth: 2)
                                    .padding(cell * 0.3)
                            } else {
                                Color.clear
                            }
                        }
                    }
                    .frame(width: cell * 0.86, height: cell * 0.86)
                    .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: cell, height: cell)
                        .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                        .onTapGesture {
                            guard session.currentPlayer == session.humanColor, !session.reversi.isOver, !session.aiThinking else { return }
                            session.playReversi(Reversi.ReversiMove(square: UInt8(idx)))
                        }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if session.currentPlayer == session.humanColor, !session.reversi.isOver, !session.aiThinking,
               session.reversi.legalMoves() == [.pass] {
                Button("我方只能停一手") { session.playReversi(.pass) }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 16)
                    .glassButtonStyle()
                    .offset(y: 24)
            }
        }
    }
}

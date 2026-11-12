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
            let pad = side / (CGFloat(n) + 1.6)
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
                    for (r, c) in starPoints(n) {
                        let cx = pad + CGFloat(c) * cell
                        let cy = pad + CGFloat(r) * cell
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)),
                                 with: .color(BoardPalette.gridLine))
                    }
                    // 坐标标注（字母列 + 数字行）
                    for i in 0..<n {
                        let pos = pad + CGFloat(i) * cell
                        let letter = Text(GoBoardView.files[i]).font(.system(size: max(8, cell * 0.30))).foregroundColor(BoardPalette.gridLine)
                        ctx.draw(ctx.resolve(letter), at: CGPoint(x: pos, y: side - pad + cell * 0.62))
                        let num = Text("\(n - i)").font(.system(size: max(8, cell * 0.30))).foregroundColor(BoardPalette.gridLine)
                        ctx.draw(ctx.resolve(num), at: CGPoint(x: pad - cell * 0.62, y: pos))
                    }
                }

                ForEach(0..<(n * n), id: \.self) { idx in
                    let r = idx / n, c = idx % n
                    Group {
                        switch go.board[idx] {
                        case 1: StoneView(color: Color(white: 0.12))
                        case 2: StoneView(color: Color(white: 0.97))
                        default: Color.clear
                        }
                    }
                    .frame(width: cell * 0.84, height: cell * 0.84)
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

    static let files = Array("abcdefghijklmnopqrst".unicodeScalars.map(String.init))

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
    // 合法着法缓存（性能：避免每次 body 重算）
    @State private var legalCache: Set<UInt8> = []
    @State private var cacheKey: Int = -1

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pad = side / (CGFloat(n) + 1.6)
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
                    let cx = pad + 7 * cell, cy = pad + 7 * cell
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7)),
                             with: .color(BoardPalette.gridLine))
                    for i in 0..<n {
                        let pos = pad + CGFloat(i) * cell
                        let letter = Text(GoBoardView.files[i]).font(.system(size: max(8, cell * 0.30))).foregroundColor(BoardPalette.gridLine)
                        ctx.draw(ctx.resolve(letter), at: CGPoint(x: pos, y: side - pad + cell * 0.62))
                        let num = Text("\(n - i)").font(.system(size: max(8, cell * 0.30))).foregroundColor(BoardPalette.gridLine)
                        ctx.draw(ctx.resolve(num), at: CGPoint(x: pad - cell * 0.62, y: pos))
                    }
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
                    .frame(width: cell * 0.66, height: cell * 0.66)
                    .position(x: pad + CGFloat(c) * cell, y: pad + CGFloat(r) * cell)
                }

                if let sq = Self.parseHintSquare(session.hintDescription ?? "") {
                    let r = sq / n, c = sq % n
                    CrosshairMark()
                        .frame(width: cell * 0.78, height: cell * 0.78)
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
        .onAppear { refreshCache(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshCache(force: true) }
        .onChange(of: session.humanFirst) { _, _ in refreshCache(force: true) }
    }

    struct CrosshairMark: View {
        var body: some View {
            ZStack {
                Circle().strokeBorder(Color.qiAccent, lineWidth: 2)
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(Color.qiAccent)
                        .frame(width: 2, height: 6)
                        .offset(y: 14)
                        .rotationEffect(.degrees(Double(i) * 90))
                }
            }
        }
    }

    /// 把 "推荐 j12" 之类的提示文本解析回格子（j12 = 列 j 行 12）
    static func parseHintSquare(_ text: String) -> Int? {
        guard text.contains("推荐") else { return nil }
        let alnum = Array(text.filter { ($0.isLetter && $0.isASCII) || $0.isNumber })
        guard alnum.count >= 2 else { return nil }
        let letters = alnum.filter { $0.isLetter }
        let digits = String(alnum.filter { $0.isNumber })
        guard let letter = letters.first,
              let idx = GoBoardView.files.firstIndex(of: String(letter)),
              let row1 = Int(digits), row1 >= 1, row1 <= 15 else { return nil }
        let row = 15 - row1
        guard row >= 0 && row < 15 else { return nil }
        return row * 15 + idx
    }

    private func refreshCache(force: Bool) {
        let key = session.gomoku.ply * 2 + session.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        guard session.currentPlayer == session.humanColor, !session.gomoku.isOver, !session.aiThinking else {
            legalCache = []
            return
        }
        legalCache = Set(session.gomoku.legalMoves().map(\.square))
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
    @State private var legalCache: Set<UInt8> = []
    @State private var cacheKey: Int = -1

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(n)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.42, blue: 0.22), Color(red: 0.07, green: 0.32, blue: 0.17)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

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
                    Group {
                        if session.reversi.black & bit != 0 {
                            StoneView(color: Color(white: 0.12))
                        } else if session.reversi.white & bit != 0 {
                            StoneView(color: Color(white: 0.97))
                        } else if legalCache.contains(UInt8(idx)) {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                                .padding(cell * 0.30)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: cell * 0.76, height: cell * 0.76)
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
        .onAppear { refreshCache(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshCache(force: true) }
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

    private func refreshCache(force: Bool) {
        let key = session.sessionPly * 2 + session.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        guard session.currentPlayer == session.humanColor, !session.reversi.isOver, !session.aiThinking else {
            legalCache = []
            return
        }
        legalCache = Set(session.reversi.legalMoves().map(\.square))
    }
}

import SwiftUI
import BoardCore

// MARK: - 国际象棋

struct ChessBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Int?
    @State private var promoCandidates: [Chess.ChessMove] = []
    @State private var legalCache: [Chess.ChessMove] = []
    @State private var cacheKey: Int = -1

    private var flip: Bool { session.humanColor == 1 }
    private var chess: Chess { session.chess }

    private func real(_ dr: Int) -> Int { flip ? 7 - dr : dr }

    private func refreshLegal(force: Bool) {
        let key = chess.ply * 2 + chess.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        legalCache = session.currentPlayer == session.humanColor && !session.aiThinking ? chess.legalMoves() : []
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8
            let legal = legalCache
            let targets: Set<Int> = selected.map { sel in Set(legal.filter { Int($0.from) == sel }.map { Int($0.to) }) } ?? []
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { dr in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { dc in
                                let r = real(dr), c = flip ? 7 - dc : dc
                                let idx = r * 8 + c
                                ZStack {
                                    Rectangle()
                                        .fill((r + c) % 2 == 0
                                              ? Color(red: 0.93, green: 0.89, blue: 0.79)
                                              : Color(red: 0.55, green: 0.44, blue: 0.32))
                                    if selected == idx {
                                        Rectangle().fill(Color.qiAccent.opacity(0.22))
                                    }
                                    if targets.contains(idx) && chess.board[idx] != 0 {
                                        RoundedRectangle(cornerRadius: cell * 0.16)
                                            .strokeBorder(Color.red.opacity(0.85), lineWidth: 2.5)
                                            .frame(width: cell * 0.94, height: cell * 0.94)
                                    }
                                    if chess.board[idx] != 0 {
                                        ChessPieceView(
                                            type: Chess.typeOf(chess.board[idx]),
                                            isWhite: Chess.colorOf(chess.board[idx]) == 0
                                        )
                                        .frame(width: cell * 0.82, height: cell * 0.82)
                                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                                    } else if targets.contains(idx) {
                                        Circle().fill(Color.qiAccent.opacity(0.4))
                                            .frame(width: cell * 0.22, height: cell * 0.22)
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture { tap(idx, legal: legal) }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { refreshLegal(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshLegal(force: true) }
        .onChange(of: session.humanFirst) { _, _ in refreshLegal(force: true) }
        .confirmationDialog("选择升变", isPresented: .init(get: { !promoCandidates.isEmpty }, set: { if !$0 { promoCandidates = [] } }), titleVisibility: .visible) {
            ForEach(promoCandidates, id: \.self) { m in
                Button(promoName(m.promotion)) { session.playChess(m); selected = nil; promoCandidates = [] }
            }
        }
    }

    private func promoName(_ p: UInt8?) -> String {
        switch p {
        case 0: return "升后"
        case 1: return "升车"
        case 2: return "升象"
        case 3: return "升马"
        default: return "升变"
        }
    }

    private func tap(_ idx: Int, legal: [Chess.ChessMove]) {
        guard session.currentPlayer == session.humanColor, !chess.isOver, !session.aiThinking else { return }
        if let sel = selected {
            let cand = legal.filter { Int($0.from) == sel && Int($0.to) == idx }
            if cand.count > 1 {
                promoCandidates = cand.sorted { ($0.promotion ?? 9) < ($1.promotion ?? 9) }
                return
            }
            if let m = cand.first {
                session.playChess(m)
                selected = nil
                return
            }
        }
        let p = chess.board[idx]
        if p != 0, Chess.colorOf(p) == session.humanColor {
            selected = (selected == idx) ? nil : idx
        } else {
            selected = nil
        }
    }
}

// MARK: - 中国象棋

/// 圆牌棋子
struct XiangqiPieceView: View {
    let text: String
    let isRed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(BoardPalette.paper)
                .overlay(Circle().strokeBorder(isRed ? Color(red: 0.75, green: 0.2, blue: 0.15) : Color.black.opacity(0.75), lineWidth: 1.6))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isRed ? Color(red: 0.72, green: 0.15, blue: 0.10) : Color.black.opacity(0.85))
        }
    }
}

struct XiangqiBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Int?
    @State private var legalCache: [Xiangqi.XiangqiMove] = []
    @State private var cacheKey: Int = -1

    private var flip: Bool { session.humanColor == 1 }
    private var game: Xiangqi { session.xiangqi }

    private func refreshLegal(force: Bool) {
        let key = game.ply * 2 + game.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        legalCache = session.currentPlayer == session.humanColor && !session.aiThinking ? game.legalMoves() : []
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cw = side / 9.0
            let ch = side / 10.0
            let legal = legalCache
            let targets: Set<Int> = selected.map { sel in Set(legal.filter { Int($0.from) == sel }.map { Int($0.to) }) } ?? []
            ZStack {
                XiangqiBoardCanvas()
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                ForEach(0..<90, id: \.self) { idx in
                    let r = flip ? idx / 9 : 9 - idx / 9
                    let c = idx % 9
                    Group {
                        if game.board[idx] != 0 {
                            XiangqiPieceView(
                                text: Self.pieceName(game.board[idx]),
                                isRed: Xiangqi.colorOf(game.board[idx]) == 0
                            )
                            .scaleEffect(selected == idx ? 1.08 : 1)
                            .overlay {
                                if targets.contains(idx) {
                                    Circle()
                                        .strokeBorder(Color.red.opacity(0.85), lineWidth: 2.5)
                                        .frame(width: cw * 0.9, height: cw * 0.9)
                                }
                            }
                        } else if targets.contains(idx) {
                            Circle().fill(Color.qiAccent.opacity(0.5))
                                .frame(width: cw * 0.22, height: cw * 0.22)
                        }
                    }
                    .frame(width: cw * 0.78, height: cw * 0.78)
                    .contentShape(Rectangle())
                    .onTapGesture { tap(idx, legal: legal) }
                    .position(x: (CGFloat(c) + 0.5) * cw, y: (CGFloat(9 - (flip ? idx / 9 : 9 - idx / 9)) + 0.5) * ch)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { refreshLegal(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshLegal(force: true) }
        .onChange(of: session.humanFirst) { _, _ in refreshLegal(force: true) }
    }

    static func pieceName(_ p: UInt8) -> String {
        let red = ["", "帥", "仕", "相", "馬", "車", "炮", "兵"]
        let black = ["", "將", "士", "象", "馬", "車", "砲", "卒"]
        let t = Int(Xiangqi.typeOf(p))
        return Xiangqi.colorOf(p) == 0 ? red[t] : black[t]
    }

    private func tap(_ idx: Int, legal: [Xiangqi.XiangqiMove]) {
        guard session.currentPlayer == session.humanColor, !game.isOver, !session.aiThinking else { return }
        if let sel = selected, let m = legal.first(where: { Int($0.from) == sel && Int($0.to) == idx }) {
            session.playXiangqi(m)
            selected = nil
            return
        }
        let p = game.board[idx]
        if p != 0, Xiangqi.colorOf(p) == session.humanColor {
            selected = (selected == idx) ? nil : idx
        } else {
            selected = nil
        }
    }
}

/// 象棋盘面（格线 + 楚河汉界）
struct XiangqiBoardCanvas: View {
    var body: some View {
        Canvas { ctx, size in
            let cw = size.width / 9, ch = size.height / 10
            var path = Path()
            for r in 0...9 {
                let y = (CGFloat(r) + 0.5) * ch
                path.move(to: CGPoint(x: cw * 0.5, y: y))
                path.addLine(to: CGPoint(x: size.width - cw * 0.5, y: y))
            }
            for c in 0...8 {
                let x = (CGFloat(c) + 0.5) * cw
                if c == 0 || c == 8 {
                    path.move(to: CGPoint(x: x, y: ch * 0.5))
                    path.addLine(to: CGPoint(x: x, y: size.height - ch * 0.5))
                } else {
                    path.move(to: CGPoint(x: x, y: ch * 0.5))
                    path.addLine(to: CGPoint(x: x, y: ch * 4.5))
                    path.move(to: CGPoint(x: x, y: ch * 5.5))
                    path.addLine(to: CGPoint(x: x, y: size.height - ch * 0.5))
                }
            }
            path.move(to: CGPoint(x: 3.5 * cw, y: 0.5 * ch)); path.addLine(to: CGPoint(x: 5.5 * cw, y: 2.5 * ch))
            path.move(to: CGPoint(x: 5.5 * cw, y: 0.5 * ch)); path.addLine(to: CGPoint(x: 3.5 * cw, y: 2.5 * ch))
            path.move(to: CGPoint(x: 3.5 * cw, y: 7.5 * ch)); path.addLine(to: CGPoint(x: 5.5 * cw, y: 9.5 * ch))
            path.move(to: CGPoint(x: 5.5 * cw, y: 7.5 * ch)); path.addLine(to: CGPoint(x: 3.5 * cw, y: 9.5 * ch))
            ctx.stroke(path, with: .color(BoardPalette.gridLine), lineWidth: 1.2)
            let river = Text("楚 河              漢 界")
                .font(.system(size: ch * 0.5, weight: .medium))
                .foregroundColor(BoardPalette.gridLine)
            ctx.draw(ctx.resolve(river), at: CGPoint(x: size.width / 2, y: size.height / 2))
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(BoardPalette.wood))
    }
}

// MARK: - 将棋

struct ShogiBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Int?
    @State private var dropType: UInt8?
    @State private var promoAsk: (from: Int, to: Int, moves: [Shogi.ShogiMove])?
    @State private var legalCache: [Shogi.ShogiMove] = []
    @State private var cacheKey: Int = -1

    private var flip: Bool { session.humanColor == 1 }
    private var game: Shogi { session.shogi }

    private func refreshLegal(force: Bool) {
        let key = game.ply * 2 + game.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        legalCache = session.currentPlayer == session.humanColor && !session.aiThinking ? game.legalMoves() : []
    }

    var body: some View {
        VStack(spacing: 10) {
            handBar(player: 1)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 9
                let legal = legalCache
                let targets: Set<Int> = selected.map { sel in
                    Set(legal.filter { $0.from != nil && Int($0.from!) == sel }.map { Int($0.to) })
                } ?? []
                let dropTargets: Set<Int> = dropType != nil
                    ? Set(legal.filter { $0.from == nil && $0.drop == dropType }.map { Int($0.to) })
                    : []
                ZStack {
                    VStack(spacing: 1) {
                        ForEach(0..<9, id: \.self) { dr in
                            HStack(spacing: 1) {
                                ForEach(0..<9, id: \.self) { dc in
                                    let c = flip ? 8 - dc : dc
                                    let r = real(dr)
                                    let idx = r * 9 + c
                                    ZStack {
                                        Rectangle().fill(Color(red: 0.94, green: 0.87, blue: 0.70))
                                        if selected == idx || dropTargets.contains(idx) {
                                            Rectangle().fill(Color.qiAccent.opacity(0.22))
                                        }
                                        if game.board[idx] != 0 {
                                            ShogiPieceView(
                                                text: Self.pieceName(game.board[idx]),
                                                isGote: Shogi.colorOf(game.board[idx]) == 1,
                                                promoted: Shogi.isPromoted(game.board[idx])
                                            )
                                            .scaleEffect(selected == idx ? 1.08 : 1)
                                            .overlay {
                                                if targets.contains(idx) {
                                                    RoundedRectangle(cornerRadius: cell * 0.14)
                                                        .strokeBorder(Color.red.opacity(0.85), lineWidth: 2.5)
                                                        .frame(width: cell * 0.94, height: cell * 0.94)
                                                }
                                            }
                                        } else if targets.contains(idx) {
                                            Circle().fill(Color.qiAccent.opacity(0.5))
                                                .frame(width: cell * 0.2, height: cell * 0.2)
                                        }
                                    }
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onTapGesture { tap(idx, legal: legal) }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
                }
                .frame(width: side, height: side)
            }
            .aspectRatio(1, contentMode: .fit)
            handBar(player: 0)
        }
        .onAppear { refreshLegal(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshLegal(force: true) }
        .onChange(of: session.humanFirst) { _, _ in refreshLegal(force: true) }
        .confirmationDialog("是否升变？", isPresented: .init(get: { promoAsk != nil }, set: { if !$0 { promoAsk = nil } }), titleVisibility: .visible) {
            if let ask = promoAsk {
                ForEach(ask.moves, id: \.self) { m in
                    Button(m.promote ? "升变" : "不升变") {
                        session.playShogi(m)
                        selected = nil
                        promoAsk = nil
                    }
                }
            }
        }
    }

    private func real(_ dr: Int) -> Int { flip ? 8 - dr : dr }

    static func pieceName(_ p: UInt8) -> String {
        let t = Int(Shogi.typeOf(p))
        if Shogi.isPromoted(p) {
            return ["", "玉", "龍", "馬", "全", "全", "圭", "杏", "と"][min(t, 8)]
        }
        return ["", "玉", "飛", "角", "金", "銀", "桂", "香", "歩"][min(t, 8)]
    }

    private func handBar(player: Int) -> some View {
        Group {
            if session.humanColor == player {
                HStack(spacing: 8) {
                    ForEach(2...8, id: \.self) { t in
                        if game.hand[player][t] > 0 {
                            Button {
                                SoundService.shared.play(.click); SoundService.shared.haptic(.uiTap)
                                dropType = (dropType == UInt8(t)) ? nil : UInt8(t)
                                selected = nil
                            } label: {
                                HStack(spacing: 3) {
                                    Text(Self.pieceName(UInt8(t)))
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("×\(game.hand[player][t])")
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(dropType == UInt8(t) ? Color.qiAccent : .primary)
                            }
                            .glassButtonStyle(cornerRadius: 14)
                        }
                    }
                }
                .frame(minHeight: 34)
            } else {
                HStack {
                    Text(player == 0 ? "先手方持驹" : "后手方持驹")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    ForEach(2...8, id: \.self) { t in
                        if game.hand[player][t] > 0 {
                            Text("\(Self.pieceName(UInt8(t)))×\(game.hand[player][t])")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 30)
            }
        }
    }

    private func tap(_ idx: Int, legal: [Shogi.ShogiMove]) {
        guard session.currentPlayer == session.humanColor, !game.isOver, !session.aiThinking else { return }
        if let dt = dropType {
            if let m = legal.first(where: { $0.from == nil && $0.drop == dt && Int($0.to) == idx }) {
                session.playShogi(m)
            }
            dropType = nil
            return
        }
        if let sel = selected {
            let cand = legal.filter { $0.from != nil && Int($0.from!) == sel && Int($0.to) == idx }
            if cand.count > 1 {
                promoAsk = (sel, idx, cand.sorted { !$0.promote && $1.promote })
                return
            }
            if let m = cand.first {
                session.playShogi(m)
                selected = nil
                return
            }
        }
        let p = game.board[idx]
        if p != 0, Shogi.colorOf(p) == session.humanColor {
            selected = (selected == idx) ? nil : idx
        } else {
            selected = nil
        }
    }
}

// MARK: - 国际跳棋

struct DraughtsBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Int?
    @State private var legalCache: [Draughts.DraughtsMove] = []
    @State private var cacheKey: Int = -1

    private var flip: Bool { session.humanColor == 0 } // 白（先手）在顶部 → 人执白时翻转到下方
    private var game: Draughts { session.draughts }

    private func refreshLegal(force: Bool) {
        let key = game.ply * 2 + game.currentPlayer
        guard force || key != cacheKey else { return }
        cacheKey = key
        legalCache = session.currentPlayer == session.humanColor && !session.aiThinking ? game.legalMoves() : []
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 10
            let legal = legalCache
            let targets: Set<Int> = selected.map { sel in
                Set(legal.filter { Int($0.path.first ?? 255) == sel }.map { Int($0.path.last ?? 255) })
            } ?? []
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { dr in
                        HStack(spacing: 0) {
                            ForEach(0..<10, id: \.self) { dc in
                                let r = flip ? 9 - dr : dr
                                let c = flip ? 9 - dc : dc
                                let idx = r * 10 + c
                                ZStack {
                                    Rectangle()
                                        .fill((r + c) % 2 == 1
                                              ? Color(red: 0.45, green: 0.30, blue: 0.18)
                                              : Color(red: 0.90, green: 0.80, blue: 0.62))
                                    if selected == idx {
                                        Rectangle().fill(Color.qiAccent.opacity(0.25))
                                    }
                                    if targets.contains(idx) {
                                        Circle().strokeBorder(Color.qiAccent, lineWidth: 2)
                                            .frame(width: cell * 0.5, height: cell * 0.5)
                                    }
                                    if game.squares[idx] != 0 {
                                        let p = game.squares[idx]
                                        StoneView(
                                            color: p == Draughts.Piece.whiteMan || p == Draughts.Piece.whiteKing
                                                ? Color(white: 0.92) : Color(white: 0.10),
                                            king: p == Draughts.Piece.whiteKing || p == Draughts.Piece.blackKing
                                        )
                                        .padding(cell * 0.10)
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture { tap(idx, legal: legal) }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { refreshLegal(force: true) }
        .onChange(of: session.sessionPly) { _, _ in refreshLegal(force: true) }
        .onChange(of: session.humanFirst) { _, _ in refreshLegal(force: true) }
    }

    private func tap(_ idx: Int, legal: [Draughts.DraughtsMove]) {
        guard session.currentPlayer == session.humanColor, !game.isOver, !session.aiThinking else { return }
        if let sel = selected {
            if let m = legal.first(where: { Int($0.path.first ?? 255) == sel && Int($0.path.last ?? 255) == idx }) {
                session.playDraughts(m)
                selected = nil
                return
            }
        }
        let p = game.squares[idx]
        if p != 0 {
            let isWhite = p == Draughts.Piece.whiteMan || p == Draughts.Piece.whiteKing
            if (session.humanColor == 0) == isWhite {
                selected = (selected == idx) ? nil : idx
                return
            }
        }
        selected = nil
    }
}

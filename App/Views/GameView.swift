import SwiftUI
import BoardCore

struct GameView: View {
    let gameID: GameID
    @StateObject private var session: GameSession
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("difficulty") private var difficultyRaw = AIDifficulty.medium.rawValue
    @AppStorage("humanFirst") private var humanFirstDefault = true
    @AppStorage("goBoardSize") private var goBoardSizeDefault = 9
    @State private var showSetup = false
    @State private var setupDone = false

    init(gameID: GameID) {
        self.gameID = gameID
        _session = StateObject(wrappedValue: GameSession(gameID: gameID))
    }

    var body: some View {
        ZStack {
            BackgroundWash()

            VStack(spacing: 12) {
                PlayersBar(session: session)
                    .padding(.horizontal, 16)

                board
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                if let hint = session.hintDescription {
                    Text(hint)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ControlBar(session: session, onNewGame: { showSetup = true }, onResign: resign)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(GameCatalogItem.all.first { $0.id == gameID }?.name ?? gameID.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSetup = true } label: { Image(systemName: "slider.horizontal.3") }
                    .glassButtonStyle()
            }
        }
        .overlay {
            if let result = session.resultText {
                ResultOverlay(text: result) {
                    showSetup = true
                } onClose: {
                    session.clearResult()
                }
            }
        }
        .sheet(isPresented: $showSetup, onDismiss: {}) {
            SetupSheet(gameID: gameID, session: session, setupDone: $setupDone) {
                session.newGame()
                setupDone = true
            }
            .presentationDetents([.medium])
            .presentationBackground(.thinMaterial)
            .interactiveDismissDisabled(!setupDone && session.sessionPly == 0)
        }
        .onAppear {
            session.difficulty = AIDifficulty(rawValue: difficultyRaw) ?? .medium
            session.humanFirst = humanFirstDefault
            session.goBoardSize = goBoardSizeDefault
            if !setupDone {
                showSetup = true
            }
        }
        .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
    }

    @ViewBuilder
    private var board: some View {
        switch gameID {
        case .go: GoBoardView(session: session)
        case .gomoku: GomokuBoardView(session: session)
        case .reversi: ReversiBoardView(session: session)
        case .chess: ChessBoardView(session: session)
        case .xiangqi: XiangqiBoardView(session: session)
        case .shogi: ShogiBoardView(session: session)
        case .draughts: DraughtsBoardView(session: session)
        }
    }

    private func resign() {
        session.resign()
    }
}

// MARK: - 顶部对局信息

struct PlayersBar: View {
    @ObservedObject var session: GameSession

    var body: some View {
        HStack(spacing: 10) {
            playerChip(
                title: "AI · \(session.difficulty.displayName)",
                subtitle: session.currentPlayer == (session.humanFirst ? 1 : 0) ? "思考中…" : "等待",
                active: session.currentPlayer != session.humanColor && !session.isOver,
                icon: "cpu"
            )
            playerChip(
                title: "你",
                subtitle: session.humanColorName,
                active: session.currentPlayer == session.humanColor && !session.isOver,
                icon: "person.fill"
            )
        }
    }

    private func playerChip(title: String, subtitle: String, active: Bool, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 19)
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(Color.qiAccent.opacity(0.8), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - 底部控制条

struct ControlBar: View {
    @ObservedObject var session: GameSession
    var onNewGame: () -> Void
    var onResign: () -> Void

    var body: some View {
        HStack {
            control("新对局", icon: "arrow.counterclockwise") { onNewGame() }
            control("提示", icon: "lightbulb") { session.requestHint() }
                .disabled(session.isOver || session.aiThinking)
            control("悔棋", icon: "undo") { session.undo() }
                .disabled(!session.canUndo || session.aiThinking)
            control("认输", icon: "flag") { onResign() }
                .disabled(session.isOver)
        }
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 28)
        .overlay {
            if session.aiThinking {
                Capsule()
                    .fill(Color.qiAccent.opacity(0.25))
                    .frame(width: 120, height: 3)
                    .offset(y: 30)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: session.aiThinking)
            }
        }
    }

    private func control(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(title == "认输" ? Color.red.opacity(0.9) : .primary)
        }
        .glassButtonStyle(cornerRadius: 20)
    }
}

// MARK: - 终局浮层

struct ResultOverlay: View {
    let text: String
    var onNewGame: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(text)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                HStack(spacing: 12) {
                    Button("再来一局") { onNewGame() }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 20)
                        .glassButtonStyle()
                    Button("复盘") { onClose() }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 20)
                        .glassButtonStyle()
                }
            }
            .padding(30)
            .liquidGlass(cornerRadius: 30)
        }
        .transition(.opacity)
    }
}

// MARK: - 开局设置

struct SetupSheet: View {
    let gameID: GameID
    @ObservedObject var session: GameSession
    @Binding var setupDone: Bool
    var onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 难度") {
                    Picker("难度", selection: $session.difficulty) {
                        ForEach(AIDifficulty.allCases, id: \.self) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("执子") {
                    Picker("先手方", selection: $session.humanFirst) {
                        Text("我先手").tag(true)
                        Text("AI 先手").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if gameID == .go {
                    Section("棋盘") {
                        Picker("路数", selection: $session.goBoardSize) {
                            Text("9 路").tag(9)
                            Text("13 路").tag(13)
                            Text("19 路").tag(19)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Button {
                    // 同步回全局默认
                    UserDefaults.standard.set(session.difficulty.rawValue, forKey: "difficulty")
                    UserDefaults.standard.set(session.humanFirst, forKey: "humanFirst")
                    UserDefaults.standard.set(session.goBoardSize, forKey: "goBoardSize")
                    setupDone = true
                    dismiss()
                    onStart()
                } label: {
                    Text("开始对局")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.primary)
            }
            .navigationTitle("新对局")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

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
                    .disabled(session.aiThinking)
                    .allowsHitTesting(!session.aiThinking)

                if let hint = session.hintDescription {
                    Text(hint)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if session.isOver && session.resultText == nil {
                    Text("对局已结束 · 点「新对局」开新一局")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 16)
                }

                DifficultyPill(session: session)

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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                session.watchdogTick()
            }
        }
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

// MARK: - 对局内难度条（填充棋盘下方空间）

struct DifficultyPill: View {
    @ObservedObject var session: GameSession

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AIDifficulty.allCases, id: \.self) { d in
                Button {
                    guard session.difficulty != d else { return }
                    SoundService.shared.play(.click); SoundService.shared.haptic(.uiTap)
                    session.difficulty = d
                    UserDefaults.standard.set(d.rawValue, forKey: "difficulty")
                } label: {
                    Text(d.displayName)
                        .font(.system(size: 12, weight: session.difficulty == d ? .semibold : .regular))
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(session.difficulty == d ? Color.primary.opacity(0.9) : Color.clear)
                        )
                        .foregroundStyle(session.difficulty == d ? colorSchemeText : .secondary)
                }
            }
        }
        .padding(4)
        .liquidGlass(cornerRadius: 20)
        .padding(.horizontal, 18)
    }

    @Environment(\.colorScheme) private var colorScheme
    private var colorSchemeText: Color { colorScheme == .dark ? .black : .white }
}

// MARK: - 顶部对局信息

struct PlayersBar: View {
    @ObservedObject var session: GameSession

    var body: some View {
        HStack(spacing: 10) {
            playerChip(
                title: "AI · \(session.difficulty.displayName)",
                subtitle: session.currentPlayer != session.humanColor && !session.isOver ? "思考中…" : "等待",
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
                    .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - 底部控制条（四个按钮统一尺寸）

struct ControlBar: View {
    @ObservedObject var session: GameSession
    var onNewGame: () -> Void
    var onResign: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            control("新对局", icon: "arrow.counterclockwise") { onNewGame() }
            control("提示", icon: "lightbulb") { session.requestHint() }
                .disabled(session.isOver || session.aiThinking)
            control("悔棋", icon: "arrow.uturn.backward") { session.undo() }
                .disabled(!session.canUndo || session.aiThinking)
            control("认输", icon: "flag", danger: true) { session.resign() }
                .disabled(session.isOver)
        }
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 28)
    }

    private func control(_ title: String, icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            SoundService.shared.play(.click); SoundService.shared.haptic(.uiTap)
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(danger ? Color.red.opacity(0.9) : .primary)
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
                Section {
                    Button {
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
                            .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.black)
                    .foregroundStyle(.white)
                } footer: {
                    Text("难度与执子将保存为默认设置").font(.system(size: 11))
                }
            }
            .navigationTitle("新对局")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

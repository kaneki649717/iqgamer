import SwiftUI
import BoardCore

struct HomeView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("difficulty") private var difficultyRaw = AIDifficulty.medium.rawValue
    @AppStorage("humanFirst") private var humanFirst = true
    @AppStorage("goBoardSize") private var goBoardSize = 9
    @State private var showSettings = false
    @State private var selectedGame: GameCatalogItem?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景（玻璃需要彩色底才明显）
                BackgroundWash()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GameCatalogItem.all) { item in
                            Button {
                                selectedGame = item
                            } label: {
                                GameCard(item: item)
                            }
                            .glassButtonStyle()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("棋境")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .glassButtonStyle()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.medium])
                    .presentationBackground(.thinMaterial)
            }
            .navigationDestination(item: $selectedGame) { item in
                GameView(gameID: item.id)
                    .onAppear {
                        // 全局设置带入对局
                        UserDefaults.standard.set(difficultyRaw, forKey: "difficulty")
                    }
            }
            .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        }
    }
}

/// 页面中性底色（黑白灰，让原生玻璃有克制的明暗变化）
struct BackgroundWash: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(white: 0.07), Color(white: 0.04)]
                : [Color(white: 0.97), Color(white: 0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            GeometryReader { geo in
                Circle()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.05 : 0.04))
                    .frame(width: geo.size.width * 1.1)
                    .blur(radius: 80)
                    .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.12)
                Circle()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.04 : 0.05))
                    .frame(width: geo.size.width)
                    .blur(radius: 90)
                    .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.6)
            }
            .ignoresSafeArea()
        }
    }
}

struct GameCard: View {
    let item: GameCatalogItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                }
                Spacer()
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(height: 108, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("difficulty") private var difficultyRaw = AIDifficulty.medium.rawValue
    @AppStorage("humanFirst") private var humanFirst = true
    @AppStorage("goBoardSize") private var goBoardSize = 9

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    Picker("外观", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("默认对局设置") {
                    Picker("AI 难度", selection: $difficultyRaw) {
                        ForEach(AIDifficulty.allCases, id: \.self) { d in
                            Text(d.displayName).tag(d.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("我执先手", isOn: $humanFirst)
                    if goBoardSize != 0 {
                        Picker("围棋棋盘", selection: $goBoardSize) {
                            Text("9 路").tag(9)
                            Text("13 路").tag(13)
                            Text("19 路").tag(19)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("引擎", value: "BoardCore · Swift 自研")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

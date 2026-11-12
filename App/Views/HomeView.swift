import SwiftUI
import BoardCore

struct HomeView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("difficulty") private var difficultyRaw = AIDifficulty.medium.rawValue
    @AppStorage("humanFirst") private var humanFirst = true
    @AppStorage("goBoardSize") private var goBoardSize = 9
    @AppStorage("stats_wins") private var statsWins = 0
    @AppStorage("stats_losses") private var statsLosses = 0
    @AppStorage("stats_draws") private var statsDraws = 0
    @State private var showSettings = false
    @State private var selectedGame: GameCatalogItem?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundWash()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(GameCatalogItem.all) { item in
                            Button {
                                SoundService.shared.play(.click); SoundService.shared.haptic(.uiTap)
                                selectedGame = item
                            } label: {
                                GameCard(item: item)
                            }
                            .glassButtonStyle()
                        }
                        statsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
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
            }
            .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        }
    }

    /// 战绩卡（填充第 8 格）
    private var statsCard: some View {
        NavigationLink {
            StatsView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.primary)
                            .frame(width: 36, height: 36)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("战绩")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("胜\(statsWins) · 负\(statsLosses) · 和\(statsDraws)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(13)
            .frame(height: 122, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassButtonStyle()
    }

    @Environment(\.colorScheme) private var colorScheme
}

/// 棋种卡（v1.1：更大、字有呼吸空间、黑白图标块强对比）
struct GameCard: View {
    let item: GameCatalogItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(scheme == .dark ? Color.white : Color.black)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            }
            Spacer(minLength: 8)
            Text(item.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(height: 122, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 战绩页
struct StatsView: View {
    @AppStorage("stats_wins") private var statsWins = 0
    @AppStorage("stats_losses") private var statsLosses = 0
    @AppStorage("stats_draws") private var statsDraws = 0

    var body: some View {
        List {
            Section("总览") {
                LabeledContent("胜", value: "\(statsWins)")
                LabeledContent("负", value: "\(statsLosses)")
                LabeledContent("和", value: "\(statsDraws)")
                let total = statsWins + statsLosses + statsDraws
                LabeledContent("总局数", value: "\(total)")
                if total > 0 {
                    LabeledContent("胜率", value: "\(Int(Double(statsWins) / Double(total) * 100))%")
                }
            }
            Section {
                Button("清空战绩", role: .destructive) {
                    SoundService.shared.play(.click)
                    statsWins = 0; statsLosses = 0; statsDraws = 0
                }
            }
        }
        .navigationTitle("战绩")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 页面中性底色
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

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("difficulty") private var difficultyRaw = AIDifficulty.medium.rawValue
    @AppStorage("humanFirst") private var humanFirst = true
    @AppStorage("goBoardSize") private var goBoardSize = 9
    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("hapticsOn") private var hapticsOn = true

    var body: some View {
        NavigationStack {
            Form {
                Section("反馈") {
                    Toggle("音效", isOn: $soundOn)
                    Toggle("震动", isOn: $hapticsOn)
                }
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
                    Picker("围棋棋盘", selection: $goBoardSize) {
                        Text("9 路").tag(9)
                        Text("13 路").tag(13)
                        Text("19 路").tag(19)
                    }
                    .pickerStyle(.segmented)
                }
                Section("关于") {
                    LabeledContent("版本", value: "1.1.0")
                    LabeledContent("引擎", value: "BoardCore · Swift 自研")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

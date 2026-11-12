import SwiftUI
import BoardCore

@main
struct QijingApp: App {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
                .tint(.qiAccent)
        }
    }
}

/// 主题：浅色 / 深色 / 跟随系统
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

extension Color {
    /// 单色主题强调色：浅色模式纯黑 / 深色模式纯白（跟随系统语义色）
    static let qiAccent = Color.primary
}

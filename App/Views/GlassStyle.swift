import SwiftUI

// MARK: - 液态玻璃样式层
// iOS 26 上用真 Liquid Glass（glassEffect）；iOS 17–25 回退 Material 毛玻璃。
// 所有玻璃视觉集中在这里，便于统一调整。

extension View {
    /// 玻璃容器（卡片 / 工具条 / 弹层）
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat, padding: CGFloat = 0) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.glassMaterial(cornerRadius: cornerRadius)
        }
        #else
        self.glassMaterial(cornerRadius: cornerRadius)
        #endif
    }

    /// Material 回退实现
    func glassMaterial(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    /// 玻璃按钮
    @ViewBuilder
    func glassButtonStyle(cornerRadius: CGFloat = 22) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(GlassFallbackButtonStyle(cornerRadius: cornerRadius))
        }
        #else
        self.buttonStyle(GlassFallbackButtonStyle(cornerRadius: cornerRadius))
        #endif
    }
}

/// Material 版玻璃按钮样式
struct GlassFallbackButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 22
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.white.opacity(configuration.isPressed ? 0.35 : 0.22), lineWidth: 0.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - 棋盘材质色

enum BoardPalette {
    /// 木纹棋盘底色（双主题）
    static var wood: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.78, blue: 0.50),
                Color(red: 0.87, green: 0.70, blue: 0.40),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var woodDark: Color { Color(red: 0.55, green: 0.42, blue: 0.22) }
    static var gridLine: Color { Color(red: 0.30, green: 0.18, blue: 0.06).opacity(0.65) }
    static var paper: Color { Color(red: 0.94, green: 0.90, blue: 0.80) }
}

// MARK: - 棋子渲染

/// 圆形棋子（围棋 / 五子棋 / 黑白棋 / 跳棋）
struct StoneView: View {
    var color: Color   // 主色
    var king = false   // 跳棋的王冠
    var selected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(1.0), color.opacity(0.82)],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0, endRadius: 60
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.5)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.0)],
                        center: UnitPoint(x: 0.34, y: 0.26),
                        startRadius: 0, endRadius: 16
                    )
                )
                .padding(14)
            if king {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.95))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
            if selected {
                Circle().strokeBorder(Color.qiAccent, lineWidth: 2.5).padding(-3)
                    .shadow(color: .white.opacity(0.85), radius: 1.6)
                    .shadow(color: .black.opacity(0.35), radius: 1.0)
            }
        }
    }
}

/// 中国象棋圆牌
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

/// 将棋驹（五边形简化为圆角瓦片，后手旋转 180°）
struct ShogiPieceView: View {
    let text: String
    let isGote: Bool
    let promoted: Bool

    var body: some View {
        ZStack {
            ShogiTileShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.93, blue: 0.80), Color(red: 0.93, green: 0.85, blue: 0.66)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(ShogiTileShape().stroke(Color.black.opacity(0.45), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.28), radius: 1.8, y: 1.2)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(promoted ? Color(red: 0.72, green: 0.15, blue: 0.10) : Color.black.opacity(0.85))
        }
        .rotationEffect(.degrees(isGote ? 180 : 0))
    }
}

struct ShogiTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.84, y: h))
        p.addLine(to: CGPoint(x: w * 0.16, y: h))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.22))
        p.closeSubpath()
        return p
    }
}

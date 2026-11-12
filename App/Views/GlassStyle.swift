import SwiftUI

// MARK: - 液态玻璃样式层
// iOS 26 上用真 Liquid Glass（glassEffect）；iOS 17–25 回退 Material 毛玻璃。

extension View {
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat) -> some View {
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

    func glassMaterial(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

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
    static var wood: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.78, blue: 0.50),
                Color(red: 0.87, green: 0.70, blue: 0.40),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static var gridLine: Color { Color(red: 0.30, green: 0.18, blue: 0.06).opacity(0.65) }
    static var paper: Color { Color(red: 0.94, green: 0.90, blue: 0.80) }
}

// MARK: - 圆形棋子（围棋/五子棋/黑白棋/跳棋）
// v1.1：渲染层精简（减少模糊层数），大棋盘不再掉帧

struct StoneView: View {
    var color: Color
    var king = false
    var selected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.85)],
                        center: UnitPoint(x: 0.36, y: 0.3),
                        startRadius: 0, endRadius: 40
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0)],
                        center: UnitPoint(x: 0.35, y: 0.28),
                        startRadius: 0, endRadius: 12
                    )
                )
                .padding(16)
            if king {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.95))
            }
            if selected {
                Circle().strokeBorder(Color.qiAccent, lineWidth: 2.5)
                    .padding(-3)
                    .shadow(color: .white.opacity(0.85), radius: 1.6)
                    .shadow(color: .black.opacity(0.35), radius: 1.0)
            }
        }
    }
}

// MARK: - 国际象棋矢量棋子（v1.2：标准 Shape，按自身 rect 归一化，无负坐标）

/// 极简矢量棋子：白子米白描黑边、黑子炭色描亮边
struct ChessPieceView: View {
    let type: UInt8   // 1兵 2马 3象 4车 5后 6王
    let isWhite: Bool

    var fill: Color { isWhite ? Color(red: 0.97, green: 0.95, blue: 0.90) : Color(red: 0.13, green: 0.13, blue: 0.16) }
    var line: Color { isWhite ? Color.black.opacity(0.7) : Color.white.opacity(0.5) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                ChessBodyShape(type: type)
                    .fill(fill)
                    .overlay(ChessBodyShape(type: type).stroke(line, lineWidth: w * 0.028))
                    .frame(width: w * 0.9, height: h * 0.74)
                    .padding(.bottom, h * 0.10)
                ChessBaseShape()
                    .fill(fill)
                    .overlay(ChessBaseShape().stroke(line, lineWidth: w * 0.028))
                    .frame(width: w * 0.62, height: h * 0.09)
                    .padding(.bottom, h * 0.015)
            }
            .frame(width: w, height: h)
        }
    }
}

/// 棋子主体（按类型切换轮廓），坐标全部基于自身 rect 的比例
struct ChessBodyShape: Shape {
    let type: UInt8

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        switch type {
        case 1: // 兵
            p.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.02, width: w * 0.30, height: w * 0.30))
            p.move(to: CGPoint(x: w * 0.28, y: h * 0.92))
            p.addQuadCurve(to: CGPoint(x: w * 0.44, y: h * 0.36), control: CGPoint(x: w * 0.28, y: h * 0.62))
            p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.36))
            p.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.92), control: CGPoint(x: w * 0.72, y: h * 0.62))
            p.closeSubpath()
        case 2: // 马
            p.move(to: CGPoint(x: w * 0.72, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))
            p.addCurve(to: CGPoint(x: w * 0.46, y: h * 0.10),
                       control1: CGPoint(x: w * 0.70, y: h * 0.38),
                       control2: CGPoint(x: w * 0.58, y: h * 0.12))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.18))
            p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.30))
            p.addCurve(to: CGPoint(x: w * 0.28, y: h * 0.55),
                       control1: CGPoint(x: w * 0.30, y: h * 0.40),
                       control2: CGPoint(x: w * 0.26, y: h * 0.46))
            p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.92))
            p.closeSubpath()
        case 3: // 象
            p.addEllipse(in: CGRect(x: w * 0.44, y: h * 0.0, width: w * 0.12, height: w * 0.12))
            p.move(to: CGPoint(x: w * 0.50, y: h * 0.12))
            p.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.52), control: CGPoint(x: w * 0.67, y: h * 0.24))
            p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.52))
            p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.12), control: CGPoint(x: w * 0.33, y: h * 0.24))
            p.closeSubpath()
        case 4: // 车
            p.move(to: CGPoint(x: w * 0.24, y: h * 0.08))
            p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.12))
            p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.12))
            p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.12))
            p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.12))
            p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.22))
            p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.08))
            p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.48))
            p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.48))
            p.closeSubpath()
        case 5: // 后
            p.move(to: CGPoint(x: w * 0.22, y: h * 0.14))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.50))
            p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.30))
            p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.52))
            p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.10))
            p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.52))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.30))
            p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.50))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.14))
            p.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.62), control: CGPoint(x: w * 0.68, y: h * 0.40))
            p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.62))
            p.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.14), control: CGPoint(x: w * 0.32, y: h * 0.40))
            p.closeSubpath()
        default: // 王
            p.move(to: CGPoint(x: w * 0.46, y: h * 0.0))
            p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.0))
            p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.07))
            p.addLine(to: CGPoint(x: w * 0.61, y: h * 0.07))
            p.addLine(to: CGPoint(x: w * 0.61, y: h * 0.15))
            p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.15))
            p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.24))
            p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.24))
            p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.15))
            p.addLine(to: CGPoint(x: w * 0.39, y: h * 0.15))
            p.addLine(to: CGPoint(x: w * 0.39, y: h * 0.07))
            p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.07))
            p.closeSubpath()
            p.move(to: CGPoint(x: w * 0.26, y: h * 0.28))
            p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.40), control: CGPoint(x: w * 0.34, y: h * 0.32))
            p.addQuadCurve(to: CGPoint(x: w * 0.74, y: h * 0.28), control: CGPoint(x: w * 0.66, y: h * 0.32))
            p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.58))
            p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.58))
            p.closeSubpath()
        }
        return p
    }
}

/// 棋子底座
struct ChessBaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height * 0.35, height: rect.height * 0.35))
        return p
    }
}

// MARK: - 将棋驹

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
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
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

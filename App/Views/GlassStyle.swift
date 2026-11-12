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

// MARK: - 国际象棋矢量棋子（v1.1 替换 unicode 字形）

/// 极简矢量棋子：白子米白描黑边、黑子炭色描亮边
struct ChessPieceView: View {
    let type: UInt8   // 1兵 2马 3象 4车 5后 6王
    let isWhite: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height
            ZStack {
                base(s).position(x: geo.size.width / 2, y: s * 0.88)
                bodyShape(s).position(x: geo.size.width / 2, y: s * 0.52)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var fill: Color { isWhite ? Color(red: 0.97, green: 0.95, blue: 0.90) : Color(red: 0.12, green: 0.12, blue: 0.15) }
    private var line: Color { isWhite ? Color.black.opacity(0.75) : Color.white.opacity(0.55) }

    private func base(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.06)
            .fill(fill)
            .frame(width: s * 0.62, height: s * 0.10)
            .overlay(RoundedRectangle(cornerRadius: s * 0.06).stroke(line, lineWidth: s * 0.025))
    }

    @ViewBuilder
    private func bodyShape(_ s: CGFloat) -> some View {
        switch type {
        case 1: pawn(s)
        case 2: knight(s)
        case 3: bishop(s)
        case 4: rook(s)
        case 5: queen(s)
        default: king(s)
        }
    }

    private func stroked(_ p: Path, _ s: CGFloat) -> some View {
        p.fill(fill).overlay(p.stroke(line, lineWidth: s * 0.03))
    }

    private func pawn(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.addEllipse(in: CGRect(x: -s * 0.14, y: -s * 0.42, width: s * 0.28, height: s * 0.28))
            path.move(to: CGPoint(x: -s * 0.20, y: s * 0.36))
            path.addQuadCurve(to: CGPoint(x: -s * 0.05, y: -s * 0.16), control: CGPoint(x: -s * 0.20, y: s * 0.05))
            path.addLine(to: CGPoint(x: s * 0.05, y: -s * 0.16))
            path.addQuadCurve(to: CGPoint(x: s * 0.20, y: s * 0.36), control: CGPoint(x: s * 0.20, y: s * 0.05))
            path.closeSubpath()
        }
        return stroked(p, s)
    }

    private func rook(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.move(to: CGPoint(x: -s * 0.26, y: -s * 0.40))
            path.addLine(to: CGPoint(x: -s * 0.26, y: -s * 0.24))
            path.addLine(to: CGPoint(x: -s * 0.14, y: -s * 0.24))
            path.addLine(to: CGPoint(x: -s * 0.14, y: -s * 0.34))
            path.addLine(to: CGPoint(x: -s * 0.05, y: -s * 0.34))
            path.addLine(to: CGPoint(x: -s * 0.05, y: -s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.05, y: -s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.05, y: -s * 0.34))
            path.addLine(to: CGPoint(x: s * 0.14, y: -s * 0.34))
            path.addLine(to: CGPoint(x: s * 0.14, y: -s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.26, y: -s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.26, y: -s * 0.40))
            path.addLine(to: CGPoint(x: s * 0.17, y: s * 0.10))
            path.addLine(to: CGPoint(x: s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.17, y: s * 0.10))
            path.closeSubpath()
        }
        return stroked(p, s)
    }

    private func knight(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.move(to: CGPoint(x: s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: s * 0.24, y: s * 0.16))
            path.addCurve(to: CGPoint(x: -s * 0.06, y: -s * 0.34),
                         control1: CGPoint(x: s * 0.22, y: -s * 0.02),
                         control2: CGPoint(x: s * 0.10, y: -s * 0.28))
            path.addLine(to: CGPoint(x: -s * 0.16, y: -s * 0.26))
            path.addLine(to: CGPoint(x: -s * 0.10, y: -s * 0.14))
            path.addCurve(to: CGPoint(x: -s * 0.24, y: s * 0.10),
                         control1: CGPoint(x: -s * 0.22, y: -s * 0.02),
                         control2: CGPoint(x: -s * 0.26, y: s * 0.02))
            path.addLine(to: CGPoint(x: -s * 0.20, y: s * 0.38))
            path.closeSubpath()
        }
        return stroked(p, s)
    }

    private func bishop(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.addEllipse(in: CGRect(x: -s * 0.06, y: -s * 0.46, width: s * 0.12, height: s * 0.12))
            path.move(to: CGPoint(x: 0, y: -s * 0.34))
            path.addQuadCurve(to: CGPoint(x: s * 0.17, y: s * 0.10), control: CGPoint(x: s * 0.16, y: -s * 0.22))
            path.addLine(to: CGPoint(x: s * 0.22, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.22, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.17, y: s * 0.10))
            path.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.34), control: CGPoint(x: -s * 0.16, y: -s * 0.22))
            path.closeSubpath()
        }
        return stroked(p, s)
    }

    private func queen(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.move(to: CGPoint(x: -s * 0.28, y: -s * 0.34))
            path.addLine(to: CGPoint(x: -s * 0.14, y: s * 0.06))
            path.addLine(to: CGPoint(x: -s * 0.28, y: -s * 0.14))
            path.addLine(to: CGPoint(x: -s * 0.08, y: s * 0.06))
            path.addLine(to: CGPoint(x: 0, y: -s * 0.38))
            path.addLine(to: CGPoint(x: s * 0.08, y: s * 0.06))
            path.addLine(to: CGPoint(x: s * 0.28, y: -s * 0.14))
            path.addLine(to: CGPoint(x: s * 0.14, y: s * 0.06))
            path.addLine(to: CGPoint(x: s * 0.28, y: -s * 0.34))
            path.addQuadCurve(to: CGPoint(x: s * 0.22, y: s * 0.16), control: CGPoint(x: s * 0.18, y: -s * 0.06))
            path.addLine(to: CGPoint(x: s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.22, y: s * 0.16))
            path.addQuadCurve(to: CGPoint(x: -s * 0.28, y: -s * 0.34), control: CGPoint(x: -s * 0.18, y: -s * 0.06))
            path.closeSubpath()
        }
        return stroked(p, s)
    }

    private func king(_ s: CGFloat) -> some View {
        let p = Path { path in
            path.move(to: CGPoint(x: -s * 0.04, y: -s * 0.52))
            path.addLine(to: CGPoint(x: s * 0.04, y: -s * 0.52))
            path.addLine(to: CGPoint(x: s * 0.04, y: -s * 0.44))
            path.addLine(to: CGPoint(x: s * 0.10, y: -s * 0.44))
            path.addLine(to: CGPoint(x: s * 0.10, y: -s * 0.36))
            path.addLine(to: CGPoint(x: s * 0.04, y: -s * 0.36))
            path.addLine(to: CGPoint(x: s * 0.04, y: -s * 0.26))
            path.addLine(to: CGPoint(x: -s * 0.04, y: -s * 0.26))
            path.addLine(to: CGPoint(x: -s * 0.04, y: -s * 0.36))
            path.addLine(to: CGPoint(x: -s * 0.10, y: -s * 0.36))
            path.addLine(to: CGPoint(x: -s * 0.10, y: -s * 0.44))
            path.addLine(to: CGPoint(x: -s * 0.04, y: -s * 0.44))
            path.closeSubpath()
            path.move(to: CGPoint(x: -s * 0.24, y: -s * 0.24))
            path.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.10), control: CGPoint(x: -s * 0.08, y: -s * 0.20))
            path.addQuadCurve(to: CGPoint(x: s * 0.24, y: -s * 0.24), control: CGPoint(x: s * 0.08, y: -s * 0.20))
            path.addLine(to: CGPoint(x: s * 0.20, y: s * 0.10))
            path.addLine(to: CGPoint(x: s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.24, y: s * 0.38))
            path.addLine(to: CGPoint(x: -s * 0.20, y: s * 0.10))
            path.closeSubpath()
        }
        return stroked(p, s)
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

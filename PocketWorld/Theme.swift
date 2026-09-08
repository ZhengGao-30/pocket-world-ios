import SwiftUI

enum Palette {
    static let ink = Color(hex: 0x1E3932)
    static let secondary = Color(hex: 0x728079)
    static let cream = Color(hex: 0xF7F8F2)
    static let mint = Color(hex: 0xDFF2C5)
    static let teal = Color(hex: 0x245A48)
    static let coral = Color(hex: 0xF48B73)
    static let lilac = Color(hex: 0xE1DDF7)
    static let lemon = Color(hex: 0xF2F6B7)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(2.5).foregroundStyle(Palette.secondary)
    }
}

struct PillLabel: View {
    let text: String
    let symbol: String
    var color: Color = Palette.mint
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.ink).padding(.horizontal, 11).padding(.vertical, 8)
            .background(color, in: Capsule())
    }
}

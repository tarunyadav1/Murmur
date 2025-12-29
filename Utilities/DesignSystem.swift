import SwiftUI

// MARK: - Design System
// Murmur's soul - consistent styling, animations, and visual language

enum MurmurDesign {

    // MARK: - Colors

    enum Colors {
        // Primary gradient - warm, voice-like feel
        static let accentGradient = LinearGradient(
            colors: [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Subtle accent for backgrounds
        static let softAccent = LinearGradient(
            colors: [Color(hex: "667eea").opacity(0.1), Color(hex: "764ba2").opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Status colors with glow
        static let success = Color(hex: "10B981")
        static let successGlow = Color(hex: "10B981").opacity(0.4)
        static let warning = Color(hex: "F59E0B")
        static let warningGlow = Color(hex: "F59E0B").opacity(0.4)
        static let error = Color(hex: "EF4444")
        static let errorGlow = Color(hex: "EF4444").opacity(0.4)

        // Voice/audio accent
        static let voicePrimary = Color(hex: "8B5CF6")
        static let voiceSecondary = Color(hex: "06B6D4")
    }

    // MARK: - Animations

    enum Animations {
        // Button interactions
        static let buttonPress = Animation.spring(duration: 0.15, bounce: 0.3)
        static let buttonRelease = Animation.spring(duration: 0.3, bounce: 0.4)

        // Panel transitions
        static let panelSlide = Animation.spring(duration: 0.4, bounce: 0.2)
        static let panelFade = Animation.easeOut(duration: 0.25)

        // Micro-interactions
        static let quick = Animation.spring(duration: 0.2, bounce: 0.2)
        static let smooth = Animation.easeInOut(duration: 0.3)

        // Breathing/ambient
        static let breathing = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
        static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

        // Toast
        static let toastIn = Animation.spring(duration: 0.5, bounce: 0.3)
        static let toastOut = Animation.easeIn(duration: 0.25)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }

    // MARK: - Shadows

    enum Shadows {
        static func soft(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.08), radius: 8, y: 4)
        }

        static func medium(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.12), radius: 16, y: 8)
        }

        static func glow(_ color: Color) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.5), radius: 12, y: 0)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    // Animated button press effect
    func pressable(isPressed: Bool) -> some View {
        self.scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(isPressed ? MurmurDesign.Animations.buttonPress : MurmurDesign.Animations.buttonRelease, value: isPressed)
    }

    // Soft glow effect
    func softGlow(_ color: Color, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        self.shadow(color: isActive ? color.opacity(0.4) : .clear, radius: radius, y: 0)
    }

    // Card style with material background
    func cardStyle(cornerRadius: CGFloat = MurmurDesign.Radius.md) -> some View {
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }

    // Breathing animation
    func breathing(isActive: Bool = true) -> some View {
        self.modifier(BreathingModifier(isActive: isActive))
    }

    // Shimmer effect for loading states
    func shimmer(isActive: Bool = true) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - Breathing Modifier

struct BreathingModifier: ViewModifier {
    let isActive: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                if isActive {
                    withAnimation(MurmurDesign.Animations.breathing) {
                        scale = 1.02
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(MurmurDesign.Animations.breathing) {
                        scale = 1.02
                    }
                } else {
                    withAnimation(MurmurDesign.Animations.quick) {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.2), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: phase * geometry.size.width * 1.5 - geometry.size.width * 0.25)
                        .blendMode(.overlay)
                    }
                    .mask(content)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
    }
}

// MARK: - Animated Button Style

struct MurmurButtonStyle: ButtonStyle {
    let variant: Variant

    enum Variant {
        case primary
        case secondary
        case ghost
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                switch variant {
                case .primary:
                    RoundedRectangle(cornerRadius: MurmurDesign.Radius.md)
                        .fill(MurmurDesign.Colors.accentGradient)
                case .secondary:
                    RoundedRectangle(cornerRadius: MurmurDesign.Radius.md)
                        .fill(.regularMaterial)
                case .ghost:
                    Color.clear
                }
            }
            .foregroundStyle(variant == .primary ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(MurmurDesign.Animations.buttonPress, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MurmurButtonStyle {
    static var murmurPrimary: MurmurButtonStyle { MurmurButtonStyle(variant: .primary) }
    static var murmurSecondary: MurmurButtonStyle { MurmurButtonStyle(variant: .secondary) }
    static var murmurGhost: MurmurButtonStyle { MurmurButtonStyle(variant: .ghost) }
}

// MARK: - Keyboard Shortcut Hint

struct KeyboardHint: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.caption2)
            .fontWeight(.medium)
            .fontDesign(.monospaced)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

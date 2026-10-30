import SwiftUI
import AppKit

// MARK: - Density Mode
public enum DensityMode: String, CaseIterable, Identifiable {
    case standard = "Geniş"
    case compact = "Kompakt"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .standard: return "rectangle.grid.1x2"
        case .compact: return "list.bullet"
        }
    }
}

// MARK: - Liquid Glass View Modifiers

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var glowColor: Color
    public var material: Material
    
    public init(cornerRadius: CGFloat = 14, glowColor: Color = .white, material: Material = .ultraThinMaterial) {
        self.cornerRadius = cornerRadius
        self.glowColor = glowColor
        self.material = material
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: glowColor.opacity(0.40), location: 0.0),
                                .init(color: glowColor.opacity(0.12), location: 0.40),
                                .init(color: .clear, location: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var glowColor: Color
    public var material: Material
    
    public init(glowColor: Color = .white, material: Material = .ultraThinMaterial) {
        self.glowColor = glowColor
        self.material = material
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(material)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: glowColor.opacity(0.50), location: 0.0),
                                .init(color: glowColor.opacity(0.15), location: 0.45),
                                .init(color: .clear, location: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 14, glowColor: Color = .white, material: Material = .ultraThinMaterial) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, glowColor: glowColor, material: material))
    }
    
    func liquidGlassCard(cornerRadius: CGFloat = 14, glowColor: Color = .white, material: Material = .ultraThinMaterial) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, glowColor: glowColor, material: material))
    }
    
    func liquidGlassCapsule(glowColor: Color = .white, material: Material = .ultraThinMaterial) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(glowColor: glowColor, material: material))
    }
    
    func studioPressable(scale: CGFloat = 0.975) -> some View {
        self.buttonStyle(StudioPressableButtonStyle(pressedScale: scale))
    }
}

// MARK: - Tactile Pressable Button Style (Impeccable Craft Floor & Native Motion)
public struct StudioPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var pressedScale: CGFloat
    
    public init(pressedScale: CGFloat = 0.975) {
        self.pressedScale = pressedScale
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
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

// MARK: - Premium High-End Design Palette
public extension Color {
    enum Premium {
        /// Refined Warm Champagne Bronze (AI Model selection, neural engines)
        public static let champagneBronze = Color(hex: "#D9A05B")
        
        /// Slate Titanium Azure (Speech Language, internationalization)
        public static let slateAzure = Color(hex: "#628EB3")
        
        /// Mineral Emerald / Muted Jade (Clipboard monitoring, active states)
        public static let emeraldMineral = Color(hex: "#449E70")
        
        /// Velvet Crimson / Muted Studio Ruby (Live audio recording, microphone)
        public static let crimsonVelvet = Color(hex: "#C25252")
        
        /// Smoked Obsidian Teal / Steel Marine (Watched folders, ingestion engine)
        public static let obsidianTeal = Color(hex: "#4E8C9C")
        
        /// Cashmere Smoked Amethyst (History & Archive, completed records)
        public static let cashmereViolet = Color(hex: "#8C71A2")
        
        /// Muted Terracotta Coral (Warnings, retries, non-fatal errors)
        public static let terracotta = Color(hex: "#BD614E")
        
        /// High-End Titanium Specular Rim (Card highlights, glass borders)
        public static let titaniumRim = Color(hex: "#E2E8F0")
        
        /// Executive Sapphire Gradient Start & End
        public static let sapphirePro = Color(hex: "#2563EB")
        public static let sapphireProDeep = Color(hex: "#1D4ED8")
    }
}

// MARK: - Floating Undo Toast View (Confirmation State in 8-State Matrix)
public struct LiquidUndoToast: View {
    public let message: String
    public let undoAction: () -> Void
    public let dismissAction: () -> Void
    
    public init(message: String, undoAction: @escaping () -> Void, dismissAction: @escaping () -> Void) {
        self.message = message
        self.undoAction = undoAction
        self.dismissAction = dismissAction
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 16))
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(L10n.tr("action_undo")) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    undoAction()
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("z", modifiers: .command)
            
            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("action_cancel"))
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassCapsule(glowColor: .accentColor, material: .regularMaterial)
        .frame(maxWidth: 460)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}


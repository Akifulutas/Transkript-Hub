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
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 14, glowColor: Color = .white, material: Material = .ultraThinMaterial) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, glowColor: glowColor, material: material))
    }
    
    func liquidGlassCapsule(glowColor: Color = .white, material: Material = .ultraThinMaterial) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(glowColor: glowColor, material: material))
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
            
            Button("Geri Al (Undo)") {
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
            }
            .buttonStyle(.plain)
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

// MARK: - Floating ⌘K Command Palette
public struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let onPasteClipboard: () -> Void
    let onSelectAudioFile: () -> Void
    let onStartQueue: () -> Void
    let onClearQueue: () -> Void
    let onCopyCurrentTranscript: () -> Void
    let onToggleFolderWatch: () -> Void
    
    public var body: some View {
        ZStack {
            // Blurred backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isPresented = false
                    }
                }
            
            // Palette Container
            VStack(spacing: 0) {
                // Search Input Header
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    TextField("Komut ara veya YouTube linki yapıştır...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text("Esc")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                Divider()
                
                // Action Items
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        paletteButton(
                            title: "Panodaki YouTube Linklerini Kuyruğa Ekle",
                            shortcut: "⌘V",
                            icon: "doc.on.clipboard"
                        ) {
                            onPasteClipboard()
                            isPresented = false
                        }
                        
                        paletteButton(
                            title: "Bilgisayardan Ses Dosyası Seç...",
                            shortcut: "⌘O",
                            icon: "waveform.badge.plus"
                        ) {
                            onSelectAudioFile()
                            isPresented = false
                        }
                        
                        paletteButton(
                            title: "Kuyruktaki Tüm İşlemleri Başlat",
                            shortcut: "⌘↩",
                            icon: "play.fill",
                            accent: true
                        ) {
                            onStartQueue()
                            isPresented = false
                        }
                        
                        paletteButton(
                            title: "Aktif Transkript Metnini Kopyala",
                            shortcut: "⌘⇧C",
                            icon: "doc.on.doc"
                        ) {
                            onCopyCurrentTranscript()
                            isPresented = false
                        }
                        
                        paletteButton(
                            title: "İzlenen Klasör Dinlemesini Aç/Kapat",
                            shortcut: "",
                            icon: "folder.badge.gearshape"
                        ) {
                            onToggleFolderWatch()
                            isPresented = false
                        }
                        
                        paletteButton(
                            title: "Kuyruğu Temizle",
                            shortcut: "",
                            icon: "trash",
                            destructive: true
                        ) {
                            onClearQueue()
                            isPresented = false
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 280)
            }
            .frame(width: 520)
            .liquidGlass(cornerRadius: 16, glowColor: .white, material: .regularMaterial)
            .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
        }
    }
    
    private func paletteButton(
        title: String,
        shortcut: String,
        icon: String,
        accent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(destructive ? .red : (accent ? .accentColor : .secondary))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13, weight: accent ? .semibold : .regular))
                    .foregroundColor(destructive ? .red : .primary)
                
                Spacer()
                
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .cornerRadius(8)
    }
}

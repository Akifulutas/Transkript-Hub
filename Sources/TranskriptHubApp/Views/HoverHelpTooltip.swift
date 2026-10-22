import SwiftUI
import AppKit

public enum TooltipPlacement: Sendable {
    case bottom
    case bottomLeading
    case bottomTrailing
    case top
    case topLeading
    case topTrailing
    
    var overlayAlignment: Alignment {
        switch self {
        case .bottom: return .bottom
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .top: return .top
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        }
    }
    
    var scaleAnchor: UnitPoint {
        switch self {
        case .bottom: return .top
        case .bottomLeading: return .topLeading
        case .bottomTrailing: return .topTrailing
        case .top: return .bottom
        case .topLeading: return .bottomLeading
        case .topTrailing: return .bottomTrailing
        }
    }
}

public struct HoverHelpTooltipModifier: ViewModifier {
    let title: String
    let description: String
    let icon: String?
    let status: String?
    let statusColor: Color
    let hint: String?
    let placement: TooltipPlacement
    let width: CGFloat
    
    @State private var isHovered: Bool = false
    @State private var showTooltip: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    
    public init(
        title: String,
        description: String,
        icon: String? = nil,
        status: String? = nil,
        statusColor: Color = .accentColor,
        hint: String? = nil,
        placement: TooltipPlacement = .bottom,
        width: CGFloat = 260
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.status = status
        self.statusColor = statusColor
        self.hint = hint
        self.placement = placement
        self.width = width
    }
    
    public func body(content: Content) -> some View {
        let activePlacement = placement
        content
            .onHover { hovering in
                handleHover(hovering)
            }
            .overlay(alignment: activePlacement.overlayAlignment) {
                if showTooltip {
                    tooltipBubble
                        .alignmentGuide(activePlacement.overlayAlignment.vertical) { d in
                            switch activePlacement {
                            case .bottom, .bottomLeading, .bottomTrailing:
                                return d[.top]
                            case .top, .topLeading, .topTrailing:
                                return d[.bottom]
                            }
                        }
                        .padding(.top, (activePlacement == .bottom || activePlacement == .bottomLeading || activePlacement == .bottomTrailing) ? 9 : 0)
                        .padding(.bottom, (activePlacement == .top || activePlacement == .topLeading || activePlacement == .topTrailing) ? 9 : 0)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: activePlacement.scaleAnchor)),
                            removal: .opacity
                        ))
                        .zIndex(99999)
                }
            }
            .help("\(title): \(description)")
            .onDisappear {
                hoverTask?.cancel()
                hoverTask = nil
                showTooltip = false
                isHovered = false
            }
    }
    
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        hoverTask = nil
        
        if hovering {
            isHovered = true
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s deliberate pause delay (not immediate on brush)
                if !Task.isCancelled && isHovered {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        showTooltip = true
                    }
                }
            }
        } else {
            isHovered = false
            withAnimation(.easeOut(duration: 0.12)) {
                showTooltip = false
            }
        }
    }
    
    private var tooltipBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Icon + Title + Status Badge
            HStack(spacing: 6) {
                if let icon = icon {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 18, height: 18)
                        Image(systemName: icon)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }
                
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 4)
                
                if let status = status {
                    Text(status)
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusColor.opacity(0.16))
                        )
                        .foregroundStyle(statusColor)
                }
            }
            
            // Description Text
            Text(description)
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(Color.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            
            // Optional Action Hint
            if let hint = hint {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    Text(hint)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 5)
        .allowsHitTesting(false)
    }
}

extension View {
    public func hoverHelpTooltip(
        title: String,
        description: String,
        icon: String? = nil,
        status: String? = nil,
        statusColor: Color = .accentColor,
        hint: String? = nil,
        placement: TooltipPlacement = .bottom,
        width: CGFloat = 260
    ) -> some View {
        self.modifier(
            HoverHelpTooltipModifier(
                title: title,
                description: description,
                icon: icon,
                status: status,
                statusColor: statusColor,
                hint: hint,
                placement: placement,
                width: width
            )
        )
    }
}

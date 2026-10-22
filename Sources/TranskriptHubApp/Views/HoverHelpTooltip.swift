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
    
    var verticalAlignmentGuide: VerticalAlignment {
        switch self {
        case .bottom, .bottomLeading, .bottomTrailing:
            return .bottom
        case .top, .topLeading, .topTrailing:
            return .top
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
        width: CGFloat = 220
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
        // Hover popover cancelled per user request; info is triggered strictly by clicking the dedicated (i) button
        content
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
        VStack(alignment: .leading, spacing: 4) {
            // Header Row: Icon + Title + Status Badge
            HStack(spacing: 5) {
                if let icon = icon {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 15, height: 15)
                        Image(systemName: icon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }
                
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 4)
                
                if let status = status {
                    Text(status)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(statusColor.opacity(0.16))
                        )
                        .foregroundStyle(statusColor)
                }
            }
            
            // Description Text
            Text(description)
                .font(.system(size: 9.5))
                .lineSpacing(1.5)
                .foregroundStyle(Color.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            // Optional Action Hint
            if let hint = hint {
                HStack(spacing: 3) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    Text(hint)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(statusColor.opacity(0.32), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 4)
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
        width: CGFloat = 220
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

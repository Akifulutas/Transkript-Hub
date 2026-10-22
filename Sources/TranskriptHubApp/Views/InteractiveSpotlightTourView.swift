import SwiftUI
import AppKit

public enum StudioTourStep: Int, CaseIterable, Identifiable, Sendable {
    case modelSelection = 0
    case languageSelection = 1
    case clipboardMonitoring = 2
    case audioRecording = 3
    case watchedFolders = 4
    case heroDropAndPaste = 5
    case queueAndTranscribe = 6
    
    public var id: Int { rawValue }
    
    public var iconName: String {
        switch self {
        case .modelSelection: return "cpu.fill"
        case .languageSelection: return "globe"
        case .clipboardMonitoring: return "doc.on.clipboard.fill"
        case .audioRecording: return "mic.fill"
        case .watchedFolders: return "folder.fill.badge.gearshape"
        case .heroDropAndPaste: return "arrow.down.doc.fill"
        case .queueAndTranscribe: return "sparkles"
        }
    }
    
    public var tintColor: Color {
        switch self {
        case .modelSelection: return .orange
        case .languageSelection: return .blue
        case .clipboardMonitoring: return .green
        case .audioRecording: return .red
        case .watchedFolders: return .teal
        case .heroDropAndPaste: return .purple
        case .queueAndTranscribe: return .accentColor
        }
    }
    
    @MainActor
    public func title(in vm: AppViewModel) -> String {
        switch self {
        case .modelSelection: return vm.t("tour_step1_title")
        case .languageSelection: return vm.t("tour_step2_title")
        case .clipboardMonitoring: return vm.t("tour_step3_title")
        case .audioRecording: return vm.t("tour_step4_title")
        case .watchedFolders: return vm.t("tour_step5_title")
        case .heroDropAndPaste: return vm.t("tour_step6_title")
        case .queueAndTranscribe: return vm.t("tour_step7_title")
        }
    }
    
    @MainActor
    public func description(in vm: AppViewModel) -> String {
        switch self {
        case .modelSelection: return vm.t("tour_step1_desc")
        case .languageSelection: return vm.t("tour_step2_desc")
        case .clipboardMonitoring: return vm.t("tour_step3_desc")
        case .audioRecording: return vm.t("tour_step4_desc")
        case .watchedFolders: return vm.t("tour_step5_desc")
        case .heroDropAndPaste: return vm.t("tour_step6_desc")
        case .queueAndTranscribe: return vm.t("tour_step7_desc")
        }
    }
}

public struct StudioTourTargetPreferenceKey: PreferenceKey {
    public static let defaultValue: [StudioTourStep: CGRect] = [:]
    public static func reduce(value: inout [StudioTourStep: CGRect], nextValue: () -> [StudioTourStep: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    @MainActor
    public func studioTourTarget(_ step: StudioTourStep) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: StudioTourTargetPreferenceKey.self,
                    value: [step: geo.frame(in: .named("StudioTourCoordinateSpace"))]
                )
            }
        )
    }
}

public struct InteractiveSpotlightTourView: View {
    @ObservedObject var viewModel: AppViewModel
    let targetFrames: [StudioTourStep: CGRect]
    
    @State private var pulseScale: CGFloat = 1.0
    
    public init(viewModel: AppViewModel, targetFrames: [StudioTourStep: CGRect]) {
        self.viewModel = viewModel
        self.targetFrames = targetFrames
    }
    
    private var currentStep: StudioTourStep {
        let stepIndex = max(0, min(viewModel.spotlightTourCurrentStep, StudioTourStep.allCases.count - 1))
        return StudioTourStep(rawValue: stepIndex) ?? .modelSelection
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let targetRect = targetFrames[currentStep] ?? CGRect(x: containerSize.width / 2 - 100, y: 30, width: 200, height: 50)
            
            ZStack {
                // 1. Inverted Mask Scrim (Darkens entire screen except the illuminated target)
                Color.black.opacity(0.72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .frame(width: targetRect.width + 12, height: targetRect.height + 12)
                            .position(x: targetRect.midX, y: targetRect.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Advance to next step when tapping anywhere outside
                        advanceStep()
                    }
                
                // 2. Animated Glowing Spotlight Border around target cutout
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [currentStep.tintColor, Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.8
                    )
                    .frame(width: targetRect.width + 12, height: targetRect.height + 12)
                    .position(x: targetRect.midX, y: targetRect.midY)
                    .shadow(color: currentStep.tintColor.opacity(0.85), radius: 10)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseScale)
                    .allowsHitTesting(false)
                
                // 3. Anchored Mission / Tutorial Card
                calloutCard(targetRect: targetRect, containerSize: containerSize)
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .onAppear {
                pulseScale = 1.025
            }
        }
    }
    
    // MARK: - Anchored Callout Mission Card
    private func calloutCard(targetRect: CGRect, containerSize: CGSize) -> some View {
        let cardWidth: CGFloat = 360
        let cardHeight: CGFloat = 210
        
        // Smart vertical positioning: below target by default, or above if target is in bottom half
        let placeBelow = (targetRect.maxY + cardHeight + 20) <= containerSize.height
        let cardY: CGFloat = placeBelow
            ? (targetRect.maxY + 16 + cardHeight / 2)
            : max(cardHeight / 2 + 16, targetRect.minY - 16 - cardHeight / 2)
        
        // Clamp horizontal position within safe margins
        let halfWidth = cardWidth / 2
        let minX = min(halfWidth + 20, containerSize.width / 2)
        let maxX = max(minX, containerSize.width - halfWidth - 20)
        let cardX = max(minX, min(maxX, targetRect.midX))
        
        return VStack(alignment: .leading, spacing: 10) {
            // Header: Step pill badge + dismiss button
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(currentStep.tintColor)
                    
                    Text(String(format: viewModel.t("tour_badge"), currentStep.rawValue + 1, StudioTourStep.allCases.count))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(currentStep.tintColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(currentStep.tintColor.opacity(0.18))
                )
                
                Spacer()
                
                Button(action: {
                    viewModel.completeSpotlightTour()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(viewModel.t("tour_skip"))
            }
            
            // Title with Colored Icon
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(currentStep.tintColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: currentStep.iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(currentStep.tintColor)
                }
                
                Text(currentStep.title(in: viewModel))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            // Mission Description
            Text(currentStep.description(in: viewModel))
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(Color.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            
            // 7 Glowing Progress Dots
            HStack(spacing: 6) {
                ForEach(StudioTourStep.allCases) { step in
                    Circle()
                        .fill(step.rawValue == currentStep.rawValue ? currentStep.tintColor : Color.primary.opacity(0.18))
                        .frame(width: step.rawValue == currentStep.rawValue ? 8 : 5, height: step.rawValue == currentStep.rawValue ? 8 : 5)
                        .scaleEffect(step.rawValue == currentStep.rawValue ? 1.2 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: currentStep)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.spotlightTourCurrentStep = step.rawValue
                            }
                        }
                }
                Spacer()
            }
            .padding(.vertical, 2)
            
            Divider()
                .padding(.vertical, 1)
            
            // Action Navigation Buttons
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.completeSpotlightTour()
                }) {
                    Text(viewModel.t("tour_skip"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if currentStep.rawValue > 0 {
                    Button(action: {
                        previousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text(viewModel.t("tour_prev"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button(action: {
                    advanceStep()
                }) {
                    HStack(spacing: 5) {
                        Text(currentStep.rawValue == StudioTourStep.allCases.count - 1 ? viewModel.t("tour_finish") : viewModel.t("tour_next"))
                            .font(.system(size: 11.5, weight: .bold))
                        if currentStep.rawValue < StudioTourStep.allCases.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [currentStep.tintColor, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [currentStep.tintColor.opacity(0.6), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        .contentShape(Rectangle())
        .position(x: cardX, y: cardY)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity
        ))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: currentStep)
    }
    
    private func advanceStep() {
        if currentStep.rawValue < StudioTourStep.allCases.count - 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                viewModel.spotlightTourCurrentStep += 1
            }
        } else {
            viewModel.completeSpotlightTour()
        }
    }
    
    private func previousStep() {
        if currentStep.rawValue > 0 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                viewModel.spotlightTourCurrentStep -= 1
            }
        }
    }
}

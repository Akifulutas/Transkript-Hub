import SwiftUI
import AppKit

// MARK: - Onboarding Step State Machine

public enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case localAI = 1
    case clipboardQueue = 2
    case watchedFolders = 3
    case liveRecording = 4
    case karaokeExport = 5
    
    public var id: Int { rawValue }
    
    public var stepIndex: Int { rawValue + 1 }
    public static var totalSteps: Int { allCases.count }
}

// MARK: - App Onboarding & Landing Tour View

public struct AppOnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isHoveringSkip: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Close Header
            topHeaderBar
            
            Divider()
                .opacity(0.4)
            
            // Dynamic Content Area with Smooth Asymmetric Slide
            ZStack {
                switch currentStep {
                case .welcome:
                    welcomeStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                case .localAI:
                    localAIStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                case .clipboardQueue:
                    clipboardQueueStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                case .watchedFolders:
                    watchedFoldersStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                case .liveRecording:
                    liveRecordingStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                case .karaokeExport:
                    karaokeExportStepView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentStep)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action & Step Navigation Bar
            bottomActionBar
        }
        .frame(width: 760, height: 530)
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor)
                
                // Subtle Ambient Glows
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.12), Color.clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 12)
    }
    
    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)
            
            Text("Transkript Hub")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text(viewModel.t("onboarding_step_counter", currentStep.stepIndex, OnboardingStep.totalSteps))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(action: {
                viewModel.completeOnboarding()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(viewModel.t("onboarding_skip") + " (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Step 0: Welcome View
    private var welcomeStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 10)
            
            // App Hero Icon & Glowing Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.Premium.sapphirePro.opacity(0.22), Color.Premium.sapphireProDeep.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.Premium.sapphirePro, Color.Premium.sapphireProDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("onboarding_welcome_badge"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                
                Text(viewModel.t("onboarding_welcome_title"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(viewModel.t("onboarding_welcome_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 580)
            }
            
            // Bento Grid: 4 Core Pillars
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 12) {
                bentoCard(
                    icon: "lock.shield.fill",
                    color: Color.Premium.emeraldMineral,
                    title: viewModel.t("onboarding_welcome_card1_title"),
                    desc: viewModel.t("onboarding_welcome_card1_desc")
                )
                bentoCard(
                    icon: "doc.on.clipboard.fill",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_welcome_card2_title"),
                    desc: viewModel.t("onboarding_welcome_card2_desc")
                )
                bentoCard(
                    icon: "folder.fill.badge.gearshape",
                    color: Color.Premium.champagneBronze,
                    title: viewModel.t("onboarding_welcome_card3_title"),
                    desc: viewModel.t("onboarding_welcome_card3_desc")
                )
                bentoCard(
                    icon: "mic.fill",
                    color: Color.Premium.crimsonVelvet,
                    title: viewModel.t("onboarding_welcome_card4_title"),
                    desc: viewModel.t("onboarding_welcome_card4_desc")
                )
            }
            .padding(.horizontal, 28)
            
            Spacer(minLength: 10)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Step 1: Local AI & Models
    private var localAIStepView: some View {
        stepTemplate(
            badge: viewModel.t("onboarding_step1_badge"),
            badgeColor: Color.Premium.champagneBronze,
            title: viewModel.t("onboarding_step1_title"),
            subtitle: viewModel.t("onboarding_step1_sub")
        ) {
            VStack(spacing: 12) {
                featureHighlightCard(
                    icon: "cpu.fill",
                    color: Color.Premium.champagneBronze,
                    title: viewModel.t("onboarding_step1_card1_title"),
                    desc: viewModel.t("onboarding_step1_card1_desc")
                )
                featureHighlightCard(
                    icon: "globe",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_step1_card2_title"),
                    desc: viewModel.t("onboarding_step1_card2_desc")
                )
                featureHighlightCard(
                    icon: "airplane",
                    color: Color.Premium.emeraldMineral,
                    title: viewModel.t("onboarding_step1_card3_title"),
                    desc: viewModel.t("onboarding_step1_card3_desc")
                )
            }
        }
    }
    
    // MARK: - Step 2: Clipboard & Queue Management
    private var clipboardQueueStepView: some View {
        stepTemplate(
            badge: viewModel.t("onboarding_step2_badge"),
            badgeColor: Color.Premium.slateAzure,
            title: viewModel.t("onboarding_step2_title"),
            subtitle: viewModel.t("onboarding_step2_sub")
        ) {
            VStack(spacing: 12) {
                featureHighlightCard(
                    icon: "doc.on.clipboard.fill",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_step2_card1_title"),
                    desc: viewModel.t("onboarding_step2_card1_desc")
                )
                featureHighlightCard(
                    icon: "arrow.down.doc.fill",
                    color: Color.Premium.obsidianTeal,
                    title: viewModel.t("onboarding_step2_card2_title"),
                    desc: viewModel.t("onboarding_step2_card2_desc")
                )
                featureHighlightCard(
                    icon: "arrow.up.arrow.down",
                    color: Color.Premium.cashmereViolet,
                    title: viewModel.t("onboarding_step2_card3_title"),
                    desc: viewModel.t("onboarding_step2_card3_desc")
                )
            }
        }
    }
    
    // MARK: - Step 3: Watched Folders & Voice Memos
    private var watchedFoldersStepView: some View {
        stepTemplate(
            badge: viewModel.t("onboarding_step3_badge"),
            badgeColor: Color.Premium.obsidianTeal,
            title: viewModel.t("onboarding_step3_title"),
            subtitle: viewModel.t("onboarding_step3_sub")
        ) {
            VStack(spacing: 12) {
                featureHighlightCard(
                    icon: "waveform.circle.fill",
                    color: Color.Premium.crimsonVelvet,
                    title: viewModel.t("onboarding_step3_card1_title"),
                    desc: viewModel.t("onboarding_step3_card1_desc")
                )
                featureHighlightCard(
                    icon: "icloud.fill",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_step3_card2_title"),
                    desc: viewModel.t("onboarding_step3_card2_desc")
                )
                featureHighlightCard(
                    icon: "bolt.badge.automatic.fill",
                    color: Color.Premium.champagneBronze,
                    title: viewModel.t("onboarding_step3_card3_title"),
                    desc: viewModel.t("onboarding_step3_card3_desc")
                )
            }
        }
    }
    
    // MARK: - Step 4: Live Recording & System Capture
    private var liveRecordingStepView: some View {
        stepTemplate(
            badge: viewModel.t("onboarding_step4_badge"),
            badgeColor: Color.Premium.crimsonVelvet,
            title: viewModel.t("onboarding_step4_title"),
            subtitle: viewModel.t("onboarding_step4_sub")
        ) {
            VStack(spacing: 12) {
                featureHighlightCard(
                    icon: "mic.fill",
                    color: Color.Premium.crimsonVelvet,
                    title: viewModel.t("onboarding_step4_card1_title"),
                    desc: viewModel.t("onboarding_step4_card1_desc")
                )
                featureHighlightCard(
                    icon: "display",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_step4_card2_title"),
                    desc: viewModel.t("onboarding_step4_card2_desc")
                )
                featureHighlightCard(
                    icon: "sparkles",
                    color: Color.Premium.cashmereViolet,
                    title: viewModel.t("onboarding_step4_card3_title"),
                    desc: viewModel.t("onboarding_step4_card3_desc")
                )
            }
        }
    }
    
    // MARK: - Step 5: Interactive Karaoke & Export
    private var karaokeExportStepView: some View {
        stepTemplate(
            badge: viewModel.t("onboarding_step5_badge"),
            badgeColor: Color.Premium.cashmereViolet,
            title: viewModel.t("onboarding_step5_title"),
            subtitle: viewModel.t("onboarding_step5_sub")
        ) {
            VStack(spacing: 12) {
                featureHighlightCard(
                    icon: "play.circle.fill",
                    color: Color.Premium.emeraldMineral,
                    title: viewModel.t("onboarding_step5_card1_title"),
                    desc: viewModel.t("onboarding_step5_card1_desc")
                )
                featureHighlightCard(
                    icon: "person.2.fill",
                    color: Color.Premium.cashmereViolet,
                    title: viewModel.t("onboarding_step5_card2_title"),
                    desc: viewModel.t("onboarding_step5_card2_desc")
                )
                featureHighlightCard(
                    icon: "folder.fill",
                    color: Color.Premium.slateAzure,
                    title: viewModel.t("onboarding_step5_card3_title"),
                    desc: viewModel.t("onboarding_step5_card3_desc")
                )
            }
        }
    }
    
    // MARK: - Template Components
    
    @ViewBuilder
    private func stepTemplate<Content: View>(
        badge: String,
        badgeColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)
            
            VStack(spacing: 6) {
                Text(badge)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor.opacity(0.12)))
                
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 580)
            }
            .padding(.horizontal, 24)
            
            content()
                .padding(.horizontal, 36)
            
            Spacer(minLength: 4)
        }
        .padding(.vertical, 8)
    }
    
    private func bentoCard(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func featureHighlightCard(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        HStack {
            // Interactive Step Indicator Dots
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { step in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            currentStep = step
                        }
                    }) {
                        Capsule()
                            .fill(currentStep == step ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: currentStep == step ? 22 : 7, height: 7)
                    }
                    .buttonStyle(.plain)
                    .help("\(step.stepIndex). \(stepTitle(for: step))")
                }
            }
            
            Spacer()
            
            // Back Button
            if currentStep != .welcome {
                Button(action: {
                    navigateToPrevious()
                }) {
                    Text(viewModel.t("onboarding_back"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Skip Tour Button
            if currentStep != .karaokeExport {
                Button(action: {
                    viewModel.completeOnboarding()
                }) {
                    Text(viewModel.t("onboarding_skip"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            
            // Primary Action Button (Continue or Launch Studio)
            Button(action: {
                navigateToNext()
            }) {
                HStack(spacing: 6) {
                    Text(currentStep == .karaokeExport ? viewModel.t("onboarding_get_started") : viewModel.t("onboarding_continue"))
                        .font(.system(size: 13, weight: .bold))
                    
                    Image(systemName: currentStep == .karaokeExport ? "sparkles" : "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: currentStep == .karaokeExport ? [Color.Premium.sapphirePro, Color.Premium.sapphireProDeep] : [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Navigation Logic
    private func navigateToNext() {
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentStep = nextStep
            }
        } else {
            viewModel.completeOnboarding()
        }
    }
    
    private func navigateToPrevious() {
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentStep = prevStep
            }
        }
    }
    
    private func stepTitle(for step: OnboardingStep) -> String {
        switch step {
        case .welcome: return viewModel.t("onboarding_welcome_title")
        case .localAI: return viewModel.t("onboarding_step1_title")
        case .clipboardQueue: return viewModel.t("onboarding_step2_title")
        case .watchedFolders: return viewModel.t("onboarding_step3_title")
        case .liveRecording: return viewModel.t("onboarding_step4_title")
        case .karaokeExport: return viewModel.t("onboarding_step5_title")
        }
    }
}

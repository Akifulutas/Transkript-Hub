import SwiftUI
import AppKit
import TranskriptHubCore

public struct AddMediaPopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isPresented: Bool
    @State private var urlText: String = ""
    @FocusState private var isUrlFieldFocused: Bool
    
    public init(viewModel: AppViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                
                Text(viewModel.t("add_media_popover_title"))
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            // YouTube / Video Link Input Section
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.t("add_media_url_label"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    
                    TextField(viewModel.t("hub_paste_url_placeholder"), text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .focused($isUrlFieldFocused)
                        .onSubmit {
                            submitUrl()
                        }
                    
                    if !urlText.isEmpty {
                        Button(action: { urlText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        submitUrl()
                    }) {
                        Text(viewModel.t("action_add"))
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            Divider()
            
            // Quick Action Buttons
            VStack(spacing: 6) {
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.addFromClipboard()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .frame(width: 18)
                        Text(viewModel.t("hub_paste_clipboard"))
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.promptForLocalAudioFiles()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.purple)
                            .frame(width: 18)
                        Text(viewModel.t("hub_choose_audio_file"))
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            isUrlFieldFocused = true
        }
    }
    
    private func submitUrl() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.quickInputText = trimmed
        viewModel.addFromQuickInput()
        urlText = ""
        isPresented = false
    }
}

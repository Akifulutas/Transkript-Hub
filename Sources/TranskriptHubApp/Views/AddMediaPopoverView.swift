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
        VStack(spacing: 8) {
            // 1. Link / YouTube Giriş Arayüzü
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.Premium.slateAzure)
                    .frame(width: 18)
                
                TextField(viewModel.t("add_media_paste_link_placeholder"), text: $urlText)
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
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            
            // 2. Ses veya Video Dosyası Seçme Arayüzü (Benzer, simetrik kart)
            Button(action: {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.promptForLocalAudioFiles()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "film.and.waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.Premium.cashmereViolet)
                        .frame(width: 18)
                    
                    Text(viewModel.t("hub_choose_audio_file"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 320)
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

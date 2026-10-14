import SwiftUI
import AppKit
import TranskriptHubCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var downloadingModel: WhisperModel? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Whisper Models Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Whisper Yapay Zeka Modelleri")
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("Modeller yerel olarak Mac'inizde saklanır ve Apple Silicon çipinizin Metal GPU hızlandırıcısını doğrudan kullanır.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        modelRow(model: .tiny, name: "Tiny", size: "75 MB", desc: "Ultra hızlı, en az bellek kullanan model")
                        Divider()
                        modelRow(model: .base, name: "Base", size: "142 MB", desc: "Hızlı, günlük kısa kayıtlar için ideal")
                        Divider()
                        modelRow(model: .small, name: "Small", size: "466 MB", desc: "Önerilen — Türkçe ve çok dilli yüksek doğruluk")
                        Divider()
                        modelRow(model: .largeV3Turbo, name: "Large-v3-Turbo", size: "1.6 GB", desc: "Maksimum doğruluk, teknik ve karmaşık konuşmalar")
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                
                // Storage Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Çıktı Dizini")
                        .font(.system(size: 14, weight: .bold))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transkript Metin Dosyaları:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(viewModel.outputWriter.defaultOutputDirectory.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button("Klasörü Aç") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: viewModel.outputWriter.defaultOutputDirectory.path)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                
                // Hardware / Engine Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Donanım ve Hızlandırma")
                        .font(.system(size: 14, weight: .bold))
                    
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Silicon Metal Hızlandırması: Aktif")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Cihaz içi yerel motor (whisper.cpp v1.9.2 Metal framework)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("M1/M2/M3/M4")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("Ayarlar")
    }
    
    private func modelRow(model: WhisperModel, name: String, size: String, desc: String) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(model)
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(size)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                    Text("Yüklü")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            } else if downloadingModel == model {
                ProgressView().controlSize(.small)
            } else {
                Button("İndir") {
                    downloadingModel = model
                    Task {
                        _ = try? await viewModel.modelManager.downloadModel(model)
                        downloadingModel = nil
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

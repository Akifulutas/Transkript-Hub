import SwiftUI
import AppKit

struct WatchedFolderView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 26))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Otomatik Klasör ve Sesli Notlar İzleme")
                            .font(.system(size: 16, weight: .bold))
                        Text("iCloud Drive veya belirlediğiniz yerel klasöre yeni bir ses dosyası eklendiğinde otomatik olarak yazıya çevrilir.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 6)
                
                // Status Card
                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(viewModel.isFolderWatching ? Color.green : Color.gray)
                                .frame(width: 10, height: 10)
                            Text(viewModel.isFolderWatching ? "Klasör İzleme Aktif (Arka Planda Dinleniyor)" : "Klasör İzleme Devre Dışı")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.isFolderWatching)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("İzlenen Dizin:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(viewModel.watchedDirectoryPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button("Finder'da Göster") {
                                let url = URL(fileURLWithPath: viewModel.watchedDirectoryPath)
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Tips / Guide Card
                VStack(alignment: .leading, spacing: 10) {
                    Label("iPhone Sesli Notlar (Voice Memos) Entegrasyonu", systemImage: "iphone")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("1. iPhone'unuzda **Ayarlar > Apple Kimliği > iCloud > Sesli Notlar** ayarının açık olduğundan emin olun.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("2. iPhone veya Apple Watch'unuzdan aldığınız bir ses kaydını iCloud Drive üzerindeki **Transkript** klasörüne paylaştığınızda Mac'iniz kaydı saniyeler içinde yazıya döker.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("3. Uygulama açık olduğu sürece (menü çubuğunda simgesi görünür), pencere kapalı olsa dahi yeni sesler arka planda sessizce işlenir.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("İzlenen Klasör")
    }
}

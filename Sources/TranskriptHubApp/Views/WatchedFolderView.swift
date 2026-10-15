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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Otomatik Klasör ve Sesli Notlar İzleme")
                            .font(.system(size: 15, weight: .bold))
                        Text("iCloud Drive veya belirlediğiniz yerel klasöre yeni sesler düştüğünde sıfır temasla transkript edilir.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // Status Card (Liquid Glass)
                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isFolderWatching ? Color.green : Color.gray)
                                    .frame(width: 9, height: 9)
                                if viewModel.isFolderWatching {
                                    Circle()
                                        .stroke(Color.green.opacity(0.4), lineWidth: 2)
                                        .frame(width: 15, height: 15)
                                }
                            }
                            
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
                                viewModel.openInFinder(path: viewModel.watchedDirectoryPath)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 14, glowColor: viewModel.isFolderWatching ? .green.opacity(0.6) : .white, material: .ultraThinMaterial)
                
                // Tips / Guide Card (Liquid Glass)
                VStack(alignment: .leading, spacing: 10) {
                    Label("iPhone Sesli Notlar (Voice Memos) Entegrasyonu", systemImage: "iphone")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("1. iPhone'unuzda **Ayarlar > Apple Kimliği > iCloud > Sesli Notlar** ayarının açık olduğundan emin olun.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("2. iPhone veya Apple Watch'tan aldığınız ses kaydını iCloud Drive üzerindeki **Transkript** klasörüne paylaştığınızda Mac'iniz kaydı anında metne döker.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("3. Uygulama açık olduğu sürece (menü çubuğu simgesi), pencere kapalı olsa dahi yeni sesler arka planda sessizce işlenir.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("İzlenen Klasör")
    }
}

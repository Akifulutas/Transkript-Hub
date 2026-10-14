import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        List(selection: $viewModel.selectedSection) {
            Section("İşlemler") {
                NavigationLink(value: SidebarSection.queue) {
                    HStack {
                        Label(SidebarSection.queue.rawValue, systemImage: SidebarSection.queue.icon)
                        Spacer()
                        
                        if viewModel.failedCount > 0 {
                            Text("\(viewModel.failedCount) Hata")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        } else if !viewModel.queueItems.isEmpty {
                            Text("\(viewModel.queueItems.count)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.18))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                
                NavigationLink(value: SidebarSection.history) {
                    HStack {
                        Label(SidebarSection.history.rawValue, systemImage: SidebarSection.history.icon)
                        Spacer()
                        if !viewModel.historyItems.isEmpty {
                            Text("\(viewModel.historyItems.count)")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("Otomasyon & Sistem") {
                NavigationLink(value: SidebarSection.watchedFolder) {
                    HStack {
                        Label(SidebarSection.watchedFolder.rawValue, systemImage: SidebarSection.watchedFolder.icon)
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(viewModel.isFolderWatching ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            if viewModel.isFolderWatching {
                                Circle()
                                    .stroke(Color.green.opacity(0.4), lineWidth: 2)
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                }
                
                NavigationLink(value: SidebarSection.settings) {
                    Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Transkript Hub")
        .safeAreaInset(edge: .bottom) {
            // Live Status Capsule at Sidebar Bottom
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isProcessing ? Color.purple : (viewModel.isFolderWatching ? Color.green : Color.gray))
                    .frame(width: 6, height: 6)
                
                Text(viewModel.isProcessing ? "İşleniyor..." : (viewModel.isFolderWatching ? "Klasör Dinleniyor" : "Hazır"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.isCommandPalettePresented.toggle()
                    }
                }) {
                    Text("⌘K")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Hızlı Komut Paletini Aç (⌘K)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        List(selection: $viewModel.selectedSection) {
            Section(viewModel.t("section_operations")) {
                NavigationLink(value: SidebarSection.queue) {
                    HStack {
                        Label(viewModel.t("section_queue"), systemImage: SidebarSection.queue.icon)
                        Spacer()
                        
                        if viewModel.failedCount > 0 {
                            Text(viewModel.t("sidebar_errors", viewModel.failedCount))
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
                        Label(viewModel.t("section_history"), systemImage: SidebarSection.history.icon)
                        Spacer()
                        if !viewModel.historyItems.isEmpty {
                            Text("\(viewModel.historyItems.count)")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section(viewModel.t("section_automation")) {
                NavigationLink(value: SidebarSection.watchedFolder) {
                    HStack {
                        Label(viewModel.t("section_watched_folder"), systemImage: SidebarSection.watchedFolder.icon)
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
                    Label(viewModel.t("section_settings"), systemImage: SidebarSection.settings.icon)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

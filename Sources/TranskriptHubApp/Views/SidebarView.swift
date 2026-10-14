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
                        if !viewModel.queueItems.isEmpty {
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
                        Circle()
                            .fill(viewModel.isFolderWatching ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                
                NavigationLink(value: SidebarSection.settings) {
                    Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Transkript Hub")
    }
}

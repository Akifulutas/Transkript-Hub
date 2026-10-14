import SwiftUI

struct HistoryListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var filteredHistory: [HistoryItem] {
        if viewModel.searchQuery.isEmpty {
            return viewModel.historyItems
        }
        return viewModel.historyItems.filter {
            $0.title.localizedCaseInsensitiveContains(viewModel.searchQuery) ||
            $0.snippet.localizedCaseInsensitiveContains(viewModel.searchQuery)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.historyItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Henüz Geçmiş Transkript Yok")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Tamamlanan tüm transkriptleriniz yerel SQLite veritabanında saklanır ve burada arşivlenir.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .padding(20)
            } else {
                List(selection: $viewModel.selectedItemID) {
                    ForEach(filteredHistory) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(formattedDate(item.date))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            if !item.snippet.isEmpty {
                                Text(item.snippet)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(item.id)
                        .contextMenu {
                            Button("Finder'da Göster") {
                                viewModel.openInFinder(path: item.outputPath)
                            }
                            Button("Metni Oku") {
                                if let content = try? String(contentsOfFile: item.outputPath, encoding: .utf8) {
                                    viewModel.copyTranscript(text: content)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Geçmiş")
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

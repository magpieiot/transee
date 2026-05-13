
import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    let isActive: Bool
    
    enum SortOrder {
        case ascending
        case descending
    }
    
    @State private var sortOrder: SortOrder = .descending
    @State private var showClearAllConfirmation = false
    @State private var searchText = ""
    @State private var isHoveringClearAll = false
    
    var sortedHistoryItems: [TranscriptionHistoryItem] {
        switch sortOrder {
        case .ascending:
            return historyManager.historyItems.sorted { $0.timestamp < $1.timestamp }
        case .descending:
            return historyManager.historyItems.sorted { $0.timestamp > $1.timestamp }
        }
    }

    var filteredHistoryItems: [TranscriptionHistoryItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sortedHistoryItems }

        return sortedHistoryItems.filter { item in
            if item.originalFileName.localizedCaseInsensitiveContains(trimmed) { return true }
            if item.modelName.localizedCaseInsensitiveContains(trimmed) { return true }
            if item.language.localizedCaseInsensitiveContains(trimmed) { return true }
            if item.outputFormat?.localizedCaseInsensitiveContains(trimmed) == true { return true }
            if item.outputFilePath?.localizedCaseInsensitiveContains(trimmed) == true { return true }
            return false
        }
    }
    
    var body: some View {
        Group {
            if isActive {
                content
                    //.searchable(text: $searchText)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                Button {
                    showClearAllConfirmation = true
                } label: {
                    Label("Clear All", systemImage: "trash.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isHoveringClearAll ? Color.crayolaRed : Color.secondary)
                .onHover { isHoveringClearAll = $0 }
                
                Button {
                    sortOrder = (sortOrder == .descending) ? .ascending : .descending
                } label: {
                    Image(systemName: sortOrder == .descending ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.munsellBlue)
                .font(.title)
                .help(sortOrder == .descending ? "Sorted by Newest First" : "Sorted by Oldest First")
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
            .padding(.horizontal, 16)
            .alert("Clear All History", isPresented: $showClearAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    historyManager.clearAll()
                }
            } message: {
                Text("Are you sure you want to clear all history records? This action cannot be undone.")
            }
            
            
            if historyManager.historyItems.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                        .padding()
                    Text("No history records yet.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredHistoryItems) { item in
                        HistoryRow(item: item)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { sortedHistoryItems[$0] }
        var indicesToDelete = IndexSet()
        for item in itemsToDelete {
            if let index = historyManager.historyItems.firstIndex(where: { $0.id == item.id }) {
                indicesToDelete.insert(index)
            }
        }
        historyManager.delete(at: indicesToDelete)
    }
}

struct HistoryRow: View {
    let item: TranscriptionHistoryItem

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.originalFileName)
                    .font(.headline)
                    .truncationMode(.middle)
                    .lineLimit(1)
                Spacer()
                Text(item.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(item.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "waveform")
                    .font(.caption)
                Text(formatDuration(item.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text(item.modelName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !item.language.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)

                    Text(item.language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let outputFormat = item.outputFormat {
                    Text(outputFormat.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(badgeColor(for: outputFormat))
                        )
                }
            }

            if let outputPath = item.outputFilePath {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(compactPath(outputPath))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .help(outputPath)

                    Spacer()

                    Button {
                        let url = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(outputPath)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .onHover { isHovering = $0 }
    }

    private var cardBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovering ? 0.08 : 0.04)
        }
        return Color.black.opacity(isHovering ? 0.06 : 0.03)
    }

    private func compactPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let file = url.lastPathComponent
        let folder = url.deletingLastPathComponent().lastPathComponent
        if folder.isEmpty { return file }
        return "\(folder) › \(file)"
    }

    private func badgeColor(for outputFormat: String) -> Color {
        switch outputFormat.lowercased() {
        case "srt":
            return Color.munsellBlue
        case "json":
            return Color.purple
        case "ass":
            return Color.orange
        case "txt", "text":
            return Color.gray
        default:
            return Color.gray
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

#Preview {
    HistoryView(isActive: true)
        .environmentObject(HistoryManager())
}

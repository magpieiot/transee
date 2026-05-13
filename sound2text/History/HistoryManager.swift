
import Foundation
import Combine
import SwiftUI

// MARK: - TranscriptionHistoryItem
struct TranscriptionHistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let originalFileName: String
    let originalFilePath: String
    let outputFilePath: String?
    let timestamp: Date
    let modelName: String
    let language: String
    let duration: Double // Duration of the audio file in seconds
    
    // Additional metadata if needed
    var outputFormat: String?
}

// MARK: - HistoryManager
@MainActor
class HistoryManager: ObservableObject {
    @Published var historyItems: [TranscriptionHistoryItem] = []
    
    private let historyFileName = "history.json"
    
    init() {
        loadHistory()
    }
    
    private var historyFileURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent(historyFileName)
    }
    
    func add(_ item: TranscriptionHistoryItem) {
        historyItems.insert(item, at: 0) // Add to the beginning
        saveHistory()
    }
    
    func delete(at offsets: IndexSet) {
        historyItems.remove(atOffsets: offsets)
        saveHistory()
    }
    
    func clearAll() {
        historyItems.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        guard let url = historyFileURL else { return }
        
        do {
            let data = try JSONEncoder().encode(historyItems)
            try data.write(to: url)
            print("History saved to \(url.path)")
        } catch {
            print("Failed to save history: \(error.localizedDescription)")
        }
    }
    
    private func loadHistory() {
        guard let url = historyFileURL else { return }
        
        if !FileManager.default.fileExists(atPath: url.path) {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            historyItems = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
            // Sort just in case, though we insert at 0
            historyItems.sort(by: { $0.timestamp > $1.timestamp })
        } catch {
            print("Failed to load history: \(error.localizedDescription)")
        }
    }
}

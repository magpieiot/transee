//
//  TranscriptionProtocols.swift
//  sound2text
//

import Foundation
import Combine

// 统一的转写片段模型，屏蔽不同底层框架的数据结构差异
public struct AppTranscriptionSegment: Identifiable, Sendable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    
    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

// 统一的转写结果模型
public struct AppTranscriptionResult: Sendable {
    public let text: String
    public let segments: [AppTranscriptionSegment]
    
    public init(text: String, segments: [AppTranscriptionSegment]) {
        self.text = text
        self.segments = segments
    }
}

// 文件转写引擎协议
@MainActor
protocol FileTranscriptionProvider: ObservableObject {
    var isTranscribing: Bool { get }
    var currentText: String { get }
    var transcriptionProgress: Double { get }
    var confirmedSegments: [AppTranscriptionSegment] { get }
    var duration: Double { get }
    
    // 我们不能直接在协议中使用 MainView.swift 中的 SelectedAudioFile 
    // 否则会产生依赖问题。既然最终我们只需要文件 URL，这里直接使用 URL
    func transcribeFile(at file: SelectedAudioFile, settings: SettingsStore) async
    func cancelTranscription()
    func resetState()
}

// 实时转写引擎协议
@MainActor
protocol LiveTranscriptionProvider: ObservableObject {
    var isTranscribing: Bool { get }
    var isRecording: Bool { get }
    var currentText: String { get }
    var confirmedText: String { get }
    var confirmedSegments: [AppTranscriptionSegment] { get }
    var bufferEnergy: [Float] { get }
    var duration: TimeInterval { get }
    var isMuted: Bool { get }
    
    func startRecording(loop: Bool, settings: SettingsStore, recordingFileURL: URL?) async
    func stopRecording(loop: Bool, settings: SettingsStore) async
    func muteMic()
    func unmuteMic()
    func resetState()
}

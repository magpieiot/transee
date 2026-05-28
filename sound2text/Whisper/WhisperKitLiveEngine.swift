//
//  WhisperKitLiveEngine.swift
//  sound2text
//

import AVFoundation
import Combine
import SwiftUI
@preconcurrency import WhisperKit

@MainActor
class WhisperKitLiveEngine: LiveTranscriptionProvider, @unchecked Sendable {
    // MARK: - 公开状态属性
    @Published var isTranscribing = false
    @Published var isRecording: Bool = false
    @Published var currentText: String = ""
    @Published var confirmedText: String = ""
    @Published var confirmedSegments: [AppTranscriptionSegment] = []
    @Published var bufferEnergy: [Float] = []
    @Published var duration: TimeInterval = 0
    @Published var isMuted: Bool = false

    // MARK: - 依赖注入
    var whisperKit: WhisperKit?
    var audioManager: AudioCaptureManager?

    // MARK: - 任务管理
    private var transcriptionTask: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var audioRecorderFile: AVAudioFile?

    // MARK: - 音频处理状态
    private var processingBuffer: [Float] = []
    private var bufferOffset: Double = 0.0
    private var durationTimer: Timer?
    
    // VAD State
    private var isTalking: Bool = false
    private var silenceDuration: Float = 0.0

    // MARK: - 公共方法

    func startRecording(loop: Bool, settings: SettingsStore, recordingFileURL: URL? = nil) async {
        guard self.whisperKit != nil, let audioManager = self.audioManager else { return }
        
        guard await PermissionManager.shared.requestMicrophonePermission() else {
            print("Microphone access was not granted.")
            return
        }

        self.resetState()

        if let url = recordingFileURL {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16000.0,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                self.audioRecorderFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            } catch {
                print("Failed to initialize audio recorder file: \(error)")
            }
        }

        do {
            try audioManager.startRecording { [weak self] newSamples in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.isMuted {
                        self.bufferEnergy = []
                    } else {
                        self.processingBuffer.append(contentsOf: newSamples)
                        // Simple energy calculation (RMS)
                        let sumSquares = newSamples.map { $0 * $0 }.reduce(0, +)
                        let rms = sqrt(sumSquares / Float(newSamples.count))
                        self.bufferEnergy = [rms]
                    }
                    
                    if let audioFile = self.audioRecorderFile {
                        let samplesToWrite = self.isMuted ? [Float](repeating: 0, count: newSamples.count) : newSamples
                        self.writeToAudioFile(samples: samplesToWrite, file: audioFile)
                    }
                }
            }
            
            self.startTimer()
            self.isRecording = true
            self.isTranscribing = true

            if loop {
                self.realtimeLoop(settings: settings)
            }
        } catch {
            print("Start Recording Error: \(error.localizedDescription)")
        }
    }

    func stopRecording(loop: Bool, settings: SettingsStore) async {
        isRecording = false
        stopRealtimeTranscription()
        stopTimer()

        audioManager?.stopRecording()
        audioRecorderFile = nil

        if !loop && !processingBuffer.isEmpty {
            transcribeTask = Task {
                isTranscribing = true
                await processAudioBuffer(isFinal: true, settings: settings)
                isTranscribing = false
            }
        } else if loop {
             Task {
                 await processAudioBuffer(isFinal: true, settings: settings)
             }
        }
    }

    func stopRealtimeTranscription() {
        isTranscribing = false
        transcriptionTask?.cancel()
    }
    
    func muteMic() {
        isMuted = true
    }
    
    func unmuteMic() {
        isMuted = false
    }
    
    private func writeToAudioFile(samples: [Float], file: AVAudioFile) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                if let baseAddr = ptr.baseAddress {
                    channelData[0].update(from: baseAddr, count: samples.count)
                }
            }
        }
        
        do {
            try file.write(from: buffer)
        } catch {
            print("Error writing to audio file: \(error)")
        }
    }
    
    func resetState() {
        currentText = ""
        confirmedText = ""
        confirmedSegments = []
        processingBuffer = []
        isTalking = false
        silenceDuration = 0
        bufferOffset = 0
        stopTimer()
        duration = 0
    }
    
    private func startTimer() {
        stopTimer()
        duration = 0
        let startTime = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.duration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func realtimeLoop(settings: SettingsStore) {
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            while isTranscribing {
                if Task.isCancelled { break }
                
                do {
                    if isMuted {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    
                    let currentDuration = Double(processingBuffer.count) / 16000.0
                    let minDuration = settings.realtimeDelayInterval > 0 ? settings.realtimeDelayInterval : 1.0
                    
                    if currentDuration > minDuration {
                        await processAudioBuffer(isFinal: false, settings: settings)
                    } else {
                         try await Task.sleep(nanoseconds: 100_000_000)
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func processAudioBuffer(isFinal: Bool, settings: SettingsStore) async {
        guard !processingBuffer.isEmpty, let whisperKit = self.whisperKit else { return }
        
        let options = createDecodingOptions(settings: settings)
        let maxSamples = 30 * 16000
        let processSamples = processingBuffer.count > maxSamples ? Array(processingBuffer.prefix(maxSamples)) : processingBuffer
        
        if processSamples.isEmpty { return }

        let decodingCallback: @Sendable (TranscriptionProgress) -> Bool? = { progress in
            Task { @MainActor in
                self.currentText = self.confirmedText + progress.text
            }
            return nil
        }
        
        do {
            let results = try await whisperKit.transcribe(
                audioArray: processSamples,
                decodeOptions: options,
                callback: decodingCallback
            )
            
            guard let result = results.first else { return }
            processSegments(result.segments, bufferDuration: Double(processSamples.count) / 16000.0, isFinal: isFinal)
            
        } catch {
            print("Transcription Error: \(error)")
        }
    }
    
    private func processSegments(_ segments: [TranscriptionSegment], bufferDuration: Double, isFinal: Bool) {
        var finalizedEndIndex: Int = 0
        var newConfirmedText = ""
        let safetyMargin: Double = 1.0
        
        for segment in segments {
            let isSafe = Double(segment.end) < (bufferDuration - safetyMargin)
            let hasPunctuation = segment.text.trimmingCharacters(in: .whitespaces).last.map { [".", "。", "?", "？", "!", "！"].contains($0) } ?? false
            
            if isFinal || isSafe || (hasPunctuation && (segment.end < (Float(bufferDuration) - 0.5))) {
                newConfirmedText += segment.text
                
                let adjustedStart = Double(segment.start) + bufferOffset
                let adjustedEnd = Double(segment.end) + bufferOffset
                
                let adjustedSegment = AppTranscriptionSegment(
                    start: adjustedStart,
                    end: adjustedEnd,
                    text: segment.text
                )
                
                confirmedSegments.append(adjustedSegment)
                
                let endSample = Int(Double(segment.end) * 16000.0)
                finalizedEndIndex = max(finalizedEndIndex, endSample)
            } else {
                break
            }
        }
        
        if finalizedEndIndex > 0 {
            confirmedText += newConfirmedText
            
            let validRemovedSamples = min(finalizedEndIndex, processingBuffer.count)
            let removedDuration = Double(validRemovedSamples) / 16000.0
            bufferOffset += removedDuration
            
            if finalizedEndIndex < processingBuffer.count {
                processingBuffer.removeFirst(finalizedEndIndex)
            } else {
                processingBuffer.removeAll()
            }
        }
    }

    private func createDecodingOptions(settings: SettingsStore) -> DecodingOptions {
        let languageCode = Constants.languages[settings.selectedLanguage, default: Constants.defaultLanguageCode]
        let task: DecodingTask = settings.selectedTask == "transcribe" ? .transcribe : .translate
        
        return DecodingOptions(
            verbose: false,
            task: task,
            language: languageCode,
            temperature: Float(settings.temperatureStart),
            temperatureFallbackCount: Int(settings.fallbackCount),
            sampleLength: Int(settings.sampleLength),
            usePrefillPrompt: settings.enablePromptPrefill,
            usePrefillCache: settings.enableCachePrefill,
            skipSpecialTokens: !settings.enableSpecialCharacters,
            withoutTimestamps: !settings.enableTimestamps,
            wordTimestamps: false
        )
    }
}

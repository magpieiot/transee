//
//  LiveTranscriptionEngine.swift
//  sound2text
//
//  Created by gavanwang on 2026/1/11.
//

import AVFoundation
import Combine
import CoreAudio
import CoreML
import CoreMedia
import SwiftUI
@preconcurrency import WhisperKit

@MainActor
class LiveTranscriptionEngine: ObservableObject, @unchecked Sendable {
    // MARK: - 公开状态属性
    @Published var isTranscribing = false  // 标记是否正在进行转写任务
    @Published var isRecording: Bool = false  // 标记是否正在录音
    @Published var currentText: String = ""  // 当前显示的完整文本（包含已确认和正在生成的）
    @Published var confirmedText: String = ""  // 已经确定的历史文本（不会再变动）
    @Published var confirmedSegments: [TranscriptionSegment] = []  // 已确认的转写片段列表
    @Published var bufferEnergy: [Float] = []  // 音频缓冲区的能量数组（用于波形显示）
    @Published var bufferSeconds: Double = 0  // 当前缓冲区的音频时长（秒）
    @Published var duration: TimeInterval = 0  // 录音总时长
    @Published var isMuted: Bool = false  // 是否静音

    // MARK: - 任务管理
    private var transcriptionTask: Task<Void, Never>?  // 实时转写的主循环任务
    private var transcribeTask: Task<Void, Never>?  // 单次转写任务（用于停止时处理剩余音频）
    private var audioRecorderFile: AVAudioFile? // 实时录音文件句柄

    // MARK: - 音频处理状态
    private var lastBufferSize: Int = 0  // 上一次从 AudioProcessor 读取的位置
    private var processingBuffer: [Float] = [] // 当前待处理的音频缓冲区（未确认部分）
    private var bufferOffset: Double = 0.0 // 累积已处理的音频时长偏移量
    private var durationTimer: Timer? // 录音计时器
    
    // VAD State
    private var isTalking: Bool = false  // 是否正在说话
    private var silenceDuration: Float = 0.0  // 无声时长

    #if os(macOS)
        private var audioDevices: [AudioDevice]?  // 可用的音频设备列表
        @Published var defaultDeviceId: AudioDeviceID?  // 默认音频输入设备 ID
        @Published var defaultDeviceName: String?  // 默认音频输入设备名称
    #endif

    // MARK: - 公共方法

    /// 开始录音并启动转写流程
    /// - Parameters:
    ///   - loop: 是否循环转写（实时模式）
    ///   - whisperKit: WhisperKit 实例
    ///   - settings: 应用设置存储
    ///   - recordingFileURL: 录音文件保存路径（可选）。如果提供，将开启实时录音写入。
    func startRecording(_ loop: Bool, whisperKit: WhisperKit, settings: SettingsStore, recordingFileURL: URL? = nil) {
        if let audioProcessor = whisperKit.audioProcessor as? AudioProcessor {
            Task(priority: .userInitiated) {
                // 1. 请求麦克风权限
                guard await PermissionManager.shared.requestMicrophonePermission() else {
                    print("Microphone access was not granted.")
                    return
                }

                // 2. 获取并设置音频输入设备
                if let defaultDevice = AudioInputDeviceManager().getDefaultAudioInputDevice() {
                    settings.selectedAudioInput = defaultDevice.name
                    print("@@@DEBUG: 系统默认音频输入设备: \(defaultDevice.name), ID: \(defaultDevice.id)") 
                    // 重置状态
                    self.resetState()

                    // 初始化录音文件
                    if let url = recordingFileURL {
                        do {
                            let settings: [String: Any] = [
                                AVFormatIDKey: kAudioFormatMPEG4AAC,
                                AVSampleRateKey: Double(WhisperKit.sampleRate),
                                AVNumberOfChannelsKey: 1,
                                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                            ]
                            // 使用 commonFormat: .pcmFormatFloat32 以便直接写入 Float 数据
                            self.audioRecorderFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                        } catch {
                            print("Failed to initialize audio recorder file: \(error)")
                        }
                    }

                    print("@@@DEBUG: Start Recording ... ... \(defaultDevice.id.description)")
                    // 3. 启动音频处理器的实时录音
                    do {
                        // 使用 nil 作为 inputDeviceID 以使用系统默认设备配置
                        // 这避免了当显式设置设备 ID 时可能出现的 "Failed to create node format" 错误
                        try audioProcessor.startRecordingLive(inputDeviceID: defaultDevice.id) { _ in
                            // UI 更新：能量条
                            Task { @MainActor in    
                                if self.isMuted {
                                    self.bufferEnergy = []
                                } else {
                                    self.bufferEnergy = whisperKit.audioProcessor.relativeEnergy
                                }
                                self.bufferSeconds = Double(whisperKit.audioProcessor.audioSamples.count) / Double(WhisperKit.sampleRate)
                            }
                        }
                        self.startTimer() // 开启计时器
                    } catch {
                        print("Start Recording Error: \(error.localizedDescription)")
                    }

                    // 4. 更新状态并启动转写循环
                    isRecording = true
                    isTranscribing = true

                    if loop {
                        realtimeLoop(whisperKit: whisperKit, settings: settings)
                    }
                }
            }
        }
    }

    /// 停止录音并结束转写任务
    func stopRecording(_ loop: Bool, whisperKit: WhisperKit, settings: SettingsStore) {
        
        isRecording = false
        stopRealtimeTranscription()

        stopRealtimeTranscription()
        stopTimer() // 停止计时器

        if let audioProcessor = whisperKit.audioProcessor as? AudioProcessor {
            audioProcessor.stopRecording()
        }
        
        // 关闭录音文件
        audioRecorderFile = nil

        // 处理剩余的缓冲区内容
        if !loop && !processingBuffer.isEmpty {
            transcribeTask = Task {
                isTranscribing = true
                await processAudioBuffer(isFinal: true, whisperKit: whisperKit, settings: settings)
                isTranscribing = false
            }
        } else if loop {
             // 如果是循环模式，最后一次强制 flush
             Task {
                 await processAudioBuffer(isFinal: true, whisperKit: whisperKit, settings: settings)
             }
        }
    }

    /// 停止实时转写任务
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
    
    // 开启录音到文件（流式）
    public func startRecordingToFile(url: URL) {
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Double(WhisperKit.sampleRate),
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            self.audioRecorderFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            print("Failed to start recording to file: \(error)")
            self.audioRecorderFile = nil
        }
    }
    
    // 关闭录音到文件
    public func stopRecordingToFile() {
        self.audioRecorderFile = nil
    }
    
    // 切换录音到文件状态（如果当前未开启，则需要提供 URL）
    public func toggleRecordingToFile(url: URL?) {
        if self.audioRecorderFile == nil {
            if let url = url {
                startRecordingToFile(url: url)
            } else {
                print("toggleRecordingToFile requires a valid URL when starting.")
            }
        } else {
            stopRecordingToFile()
        }
    }
    
    /// 辅助方法：写入音频数据到文件
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
    
    private func resetState() {
        currentText = ""
        confirmedText = ""
        confirmedSegments = []
        processingBuffer = []
        lastBufferSize = 0
        isTalking = false
        lastBufferSize = 0
        isTalking = false
        silenceDuration = 0
        bufferOffset = 0
        stopTimer()
        duration = 0
    }
    
    // MARK: - Timer Logic
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

    /// 实时转写循环
    func realtimeLoop(whisperKit: WhisperKit, settings: SettingsStore) {
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            while isTranscribing {
                if Task.isCancelled { break }
                
                do {
                    // 从 AudioProcessor 获取新数据
                    let globalBuffer = whisperKit.audioProcessor.audioSamples
                    let newSampleCount = globalBuffer.count - lastBufferSize
                    
                    if newSampleCount > 0 {
                        let newSamples = Array(globalBuffer[lastBufferSize..<globalBuffer.count])
                        
                        // 实时写入文件
                        if let audioFile = self.audioRecorderFile {
                            let samplesToWrite = isMuted ? [Float](repeating: 0, count: newSamples.count) : newSamples
                            self.writeToAudioFile(samples: samplesToWrite, file: audioFile)
                        }

                        if !isMuted {
                            processingBuffer.append(contentsOf: newSamples)
                        }
                        lastBufferSize = globalBuffer.count
                    } else if newSampleCount < 0 {
                        // Buffer reset detected
                        lastBufferSize = 0
                        processingBuffer = [] // Reset local buffer too as audio source changed
                        continue
                    }
                    
                    if isMuted {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    
                    // 检查是否有足够的音频进行处理 (例如 1.0 秒)
                    let currentDuration = Double(processingBuffer.count) / Double(WhisperKit.sampleRate)
                    // 使用设置中的延迟间隔，默认可能是 2s
                    let minDuration = settings.realtimeDelayInterval > 0 ? settings.realtimeDelayInterval : 1.0
                    
                    if currentDuration > minDuration {
                        // VAD Check
                        var shouldTranscribe = true
                        
                        if settings.useVAD {
                           let isVoice = AudioProcessor.isVoiceDetected(
                               in: whisperKit.audioProcessor.relativeEnergy,
                               nextBufferInSeconds: Float(currentDuration),
                               silenceThreshold: Float(settings.silenceThreshold)
                           )
                           
                           if isVoice {
                               isTalking = true
                               silenceDuration = 0
                           } else {
                               silenceDuration += Float(currentDuration)
                               isTalking = false
                               
                               // 如果检测到一段时间的静音，且缓冲区有内容，这是分割句子的好时机
                               // 但如果静音时间太短，可能只是停顿
                               if silenceDuration > 0.5 {
                                    shouldTranscribe = true // 也是时候处理了
                               } else {
                                    // 只是短暂静音，且不是说话中，可能没必要频繁触发？
                                    // 不，为了实时性，只要在这个分支，我们通常还是看看
                                    // 但为了节省CPU，如果纯静音且没多少新数据，可以跳过
                                    // 这里保留逻辑：只要有足够 accumulated 数据，就处理，让 processAudioBuffer 决定是否 finalize
                               }
                           }
                        }
                        
                        if shouldTranscribe {
                            await processAudioBuffer(isFinal: false, whisperKit: whisperKit, settings: settings)
                        } else {
                            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        }
                    } else {
                        // 等待更多数据
                         try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                    
                } catch {
                    print("Realtime Loop Error: \(error)")
                    break
                }
            }
        }
    }

    /// 处理当前的音频缓冲区
    /// - isFinal: 是否是最后一次处理（强行结束）
    func processAudioBuffer(isFinal: Bool, whisperKit: WhisperKit, settings: SettingsStore) async {
        guard !processingBuffer.isEmpty else { return }
        
        let options = createDecodingOptions(settings: settings)
        
        // 限制最大处理长度，防止 OOM 或超长推理
        // Whisper 最大窗口 30s。
        let maxSamples = 30 * WhisperKit.sampleRate
        let processSamples = processingBuffer.count > maxSamples ? Array(processingBuffer.prefix(maxSamples)) : processingBuffer
        
        if processSamples.isEmpty { return }

        // 回调，用于实时显示 token (可选，如果 WhisperKit 支持)
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
            
            // 结果确认逻辑 (Stability/Finalization Logic)
            processSegments(result.segments, bufferDuration: Double(processSamples.count) / Double(WhisperKit.sampleRate), isFinal: isFinal)
            
        } catch {
            print("Transcription Error: \(error)")
        }
    }
    
    /// 分析片段并确认稳定的部分
    private func processSegments(_ segments: [TranscriptionSegment], bufferDuration: Double, isFinal: Bool) {
        var finalizedEndIndex: Int = 0
        var newConfirmedText = ""
        
        // 安全边际：如果片段结束时间距离音频末尾超过 1.0 秒，认为该片段已稳定
        // 这个值越小，确认越快，但可能把没说完的词截断
        let safetyMargin: Double = 1.0
        
        for segment in segments {
            // 检查片段是否在安全区域内 (结束时间 < 总时长 - 安全边际)
            let isSafe = Double(segment.end) < (bufferDuration - safetyMargin)
            
            // 检查是否有标点符号，通常意味着句子结束
            let hasPunctuation = segment.text.trimmingCharacters(in: .whitespaces).last.map { [".", "。", "?", "？", "!", "！"].contains($0) } ?? false
            
            // 决定是否确认该片段
            // 1. 如果是 isFinal (停止录音)，无条件确认
            // 2. 如果片段在安全区内（也就是还没到最新录入的音频边缘）
            // 3. 如果片段有明显结束标点，且离边缘也有一定距离 (0.5s)，防止标点是误判
            if isFinal || isSafe || (hasPunctuation && (segment.end < (Float(bufferDuration) - 0.5))) {
                
                // 确认此片段
                newConfirmedText += segment.text
                
                // 记录确认的片段
                // 这里的 key fix: 将局部 buffer 时间戳转换为全局时间戳
                let adjustedStart = segment.start + Float(bufferOffset)
                let adjustedEnd = segment.end + Float(bufferOffset)
                
                let adjustedSegment = TranscriptionSegment(
                    id: segment.id,
                    seek: segment.seek,
                    start: adjustedStart,
                    end: adjustedEnd,
                    text: segment.text,
                    tokens: segment.tokens,
                    temperature: segment.temperature,
                    avgLogprob: segment.avgLogprob,
                    compressionRatio: segment.compressionRatio,
                    noSpeechProb: segment.noSpeechProb,
                    words: segment.words?.map { word in
                        var newWord = word
                        newWord.start += Float(bufferOffset)
                        newWord.end += Float(bufferOffset)
                        return newWord
                    }
                )
                
                confirmedSegments.append(adjustedSegment)
                print("@@@DEBUG: New Confirmed segment: \(adjustedStart) - \(adjustedEnd) : \(segment.text)")
                // 计算需要移除的样本数
                let endSample = Int(Double(segment.end) * Double(WhisperKit.sampleRate))
                finalizedEndIndex = max(finalizedEndIndex, endSample)
            } else {
                // 如果当前片段不稳定，后续的通常也不稳定，不再继续确认
                break
            }
        }
        
        // 更新状态
        if finalizedEndIndex > 0 {
            confirmedText += newConfirmedText
            
            // 更新偏移量
            let validRemovedSamples = min(finalizedEndIndex, processingBuffer.count)
            let removedDuration = Double(validRemovedSamples) / Double(WhisperKit.sampleRate)
            bufferOffset += removedDuration
            
            // 从 processingBuffer 中移除已确认的音频
            if finalizedEndIndex < processingBuffer.count {
                processingBuffer.removeFirst(finalizedEndIndex)
            } else {
                processingBuffer.removeAll()
            }
        }
        
        // 任何剩余的片段或未确认部分，将显示在 confirmedText 之后
        // 在 processAudioBuffer 的 callback 中已经更新了 currentText
        // 但这里我们需要确保 currentText 在 loop 结束时是正确的
        // 如果我们移除了一些 buffer，我们需要确保下一次显示不会跳变
        // 实际上下次 loop 的 preview 会基于新的 short buffer，所以 currentText = confirmedText + new_short_preview
        // 这里暂时不需要手动 set currentText，因为下一次 process 很快会刷新它。
        // 但为了防止闪烁，我们可以保留当前的 residual text as preview?
        // 简化起见，等待下一次 callback 刷新即可。
    }

    private func createDecodingOptions(settings: SettingsStore) -> DecodingOptions {
        let languageCode = Constants.languages[settings.selectedLanguage, default: Constants.defaultLanguageCode]
        let task: DecodingTask = settings.selectedTask == "transcribe" ? .transcribe : .translate
        
        // 实时模式下，我们希望低延迟
        // 禁用 prompt prefill 可能更好，除非有强烈的上下文需求，
        // 因为 sliding window 本身就把上下文切断了。
        // 不过 prompt prefill 可以把 confirmedText 的末尾几个词喂给模型，增加连贯性。
        // 这里先简化，只用基本配置。
        
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
            wordTimestamps: false // 简化模式下不强制词级时间戳，由 segment 级处理足矣 (除非 UI 需要高亮)
        )
    }

    // MARK: - Helper Methods
}

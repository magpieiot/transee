//
//  WhisperKitFileEngine.swift
//  transee
//
//  Created by gavanwang on 2026/2/13.
//
import AVFoundation
import CoreAudio
import Foundation
import Combine
@preconcurrency import WhisperKit

// MARK: - 转写引擎 (TranscriptionEngine)
// 负责处理音频转写任务、管理转写状态和结果
@MainActor
class WhisperKitFileEngine: FileTranscriptionProvider, @unchecked Sendable {
    @Published var isTranscribing = false  // 是否正在转写
    @Published var isRecording: Bool = false  // 是否正在录音
    @Published var currentText = ""
    @Published var confirmedText: String = ""  // 已确认的文本
    @Published var confirmedSegments: [AppTranscriptionSegment] = []
    // 新增：转写计时器时长
    @Published var duration: Double = 0.0
    // 用于存储转录进度的属性
    @Published var transcriptionProgress: Double = 0.0
    @Published var isMuted: Bool = false  // 是否静音
    
    // WhisperKit instance injected by TranscriptionService
    var whisperKit: WhisperKit?

    /// 实时转写过程中，按“窗口 ID → (该窗口已产生的文本数组, 累计回退次数)”形式缓存各音频块信息
    /// - key (Int): WhisperKit 每次滑动窗口给出的 windowId，代表当前正在处理的音频块序号
    /// - value: 该窗口已产生的文本数组，用于拼接或回退时快速替换
    private var currentChunks: [Int: String] = [:]
    //private var transcriptionTask: Task<Void, Never>?  // 实时转写的主循环任务  
    private var transcribeTask: Task<Void, Never>?
    //private var audioRecorderFile: AVAudioFile? // 实时录音文件句柄

    private var tokensPerSecond: TimeInterval = 0  // 每秒令牌数
    private var firstTokenTime: TimeInterval = 0  // 首个令牌时间
    private var modelLoadingTime: TimeInterval = 0  // 模型加载时间
    private var pipelineStart: TimeInterval = 0  // 管道启动时间
    private var effectiveRealTimeFactor: TimeInterval = 0  // 有效实时因子
    private var effectiveSpeedFactor: TimeInterval = 0  // 有效速度因子
    private var totalInferenceTime: TimeInterval = 0  // 总推理时间
    private var currentLag: TimeInterval = 0  // 当前延迟

    // 处理统计相关
    private var currentFallbacks: Int = 0  // 当前回退次数
    private var currentEncodingLoops: Int = 0  // 当前编码循环次数
    private var currentDecodingLoops: Int = 0  // 当前解码循环次数
    private var lastConfirmedSegmentEndSeconds: Float = 0  // 最后确认段结束时间
    //private var requiredSegmentsForConfirmation: Int = 4  // 确认所需段数
    //private var bufferEnergy: [Float] = []  // 缓冲区能量
    //private var bufferSeconds: Double = 0  // 缓冲区秒数

    // MARK: - 音频处理状态
    //private var lastBufferSize: Int = 0  // 上一次从 AudioProcessor 读取的位置
    //private var processingBuffer: [Float] = [] // 当前待处理的音频缓冲区（未确认部分）
    //private var bufferOffset: Double = 0.0 // 累积已处理的音频时长偏移量
    //private var durationTimer: Timer? // 录音计时器

    #if os(macOS)
            private var audioDevices: [AudioDevice]?  // 音频设备列表(仅macOS)
            @Published var defaultDeviceId: AudioDeviceID?  // 默认音频设备ID(仅macOS)
            @Published var defaultDeviceName: String?  // 默认音频设备名称(仅macOS)
    #endif
    

    private var transcribeTimer: Timer?
    private var countTimer: Int = 0
    let id = UUID()
    // 新增：音频总时长（秒）
    var totalAudioDuration: Double = 0.0
    // 新增：当前转写的最大时间戳
    private var currentMaxTimestamp: Double = 0.0
    private var isStreamMode: Bool = true

    /// 启动转写计时器
    func timerStart() {
        let beginTime = Date().timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }  // 避免循环引用
            Task { @MainActor in
                self.duration = Double(Date().timeIntervalSinceReferenceDate - beginTime)
            }
        }
        self.transcribeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        //print("@@@DEBUG: 计时器更新: ID:\(self.transcribeTimer?.description)")
    }

    /// 停止转写计时器
    func timerStop() {
        if let timer = transcribeTimer {
            timer.invalidate()
            //print("@@@DEBUG: 计时器更新: \(timerText), 计时器停止, \(self.id)")
        }
        transcribeTimer = nil  // 最佳实践是将其置为 nil
    }

    func resetState() {
        print("resetState: 清空 currentChunks 之前 count=\(currentChunks.count)")
        transcribeTask?.cancel()
        isRecording = false
        isTranscribing = false
        if let audioProcessor = whisperKit?.audioProcessor as? AudioProcessor {
            audioProcessor.stopRecording()
        }
        currentText = ""
        currentChunks = [:]
        confirmedSegments = []
        currentFallbacks = 0
        currentMaxTimestamp = 0.0
        //lastBufferSize = 0
        transcribeTimer = nil
    }

    /// 计算基于时间戳的转写进度
    /// - Parameter segments: 当前的转写片段
    private func updateTranscriptionProgress(with segments: [TranscriptionSegment]) {
        guard totalAudioDuration > 0 else {
            transcriptionProgress = 0.0
            return
        }
        // 找到最新的片段结束时间
        let maxEndTime = segments.map { $0.end }.max() ?? 0.0
        currentMaxTimestamp = Double(maxEndTime) + currentMaxTimestamp

        // 计算进度百分比
        transcriptionProgress = min(Double(currentMaxTimestamp) / totalAudioDuration, 1.0)
        //print("转写进度: \(String(format: "%.1f", transcriptionProgress * 100))% (\(String(format: "%.2f", currentMaxTimestamp))s / \(String(format: "%.2f", totalAudioDuration))s)")
    }

    /// 转写音频文件
    /// - Parameter path: 音频文件路径
    func transcribeFile(at file: SelectedAudioFile, settings: SettingsStore) {
        // 重置状态
        resetState()
        transcriptionProgress = 0.0
        guard let whisperKit = self.whisperKit else { return }
        // 初始化音频处理器
        whisperKit.audioProcessor = AudioProcessor()
        // 创建转写任务
        transcribeTask = Task {
            isTranscribing = true
            timerStart()
            defer { timerStop() }
            do {
                // 计算音频总时长
                let mediaType = try await identifyMediaFileType(at: file.fileUrl)
                totalAudioDuration = await calculateAudioDuration(from: file.fileUrl).0
                print("@@@DEBUG: 文件类型: \(mediaType)，音频总时长: \(totalAudioDuration)")
                try await transcribeCurrentFile_Video(
                    file: file, whisperKit: whisperKit, settings: settings)
                // 检查是否已取消
                try Task.checkCancellation()
            } catch is CancellationError {
                // 取消时快速退出并重置常用状态
                Logging.debug("Transcription cancelled by user.")
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptionProgress = 0.0
                    self.currentText = ""
                    self.currentChunks.removeAll()
                }
                return
            } catch {
                print("File selection error: \(error.localizedDescription)")
            }
            isTranscribing = false
            transcriptionProgress = 1.0  // 转写完成
            print(
                "@@@DEBUG: 转写进度更新4: \(String(format: "%.1f", self.transcriptionProgress * 100))%, Duration: \(self.duration)"
            )
        }
    }

    /// 切换录音状态
    /// - Parameter shouldLoop: 是否循环录音
    /*
    func toggleRecording(shouldLoop: Bool, whisperKit: WhisperKit, settings: SettingsStore) {
            print("@@@DEBUG: 切换录音状态: isRecording=\(isRecording), isTranscribing=\(isTranscribing)")
            isRecording.toggle()
    
            if isRecording {
                    resetState(whisperKit: whisperKit, settings: settings)
                    startRecording(shouldLoop, whisperKit: whisperKit, settings: settings)
            } else {
                    stopRecording(shouldLoop, whisperKit: whisperKit, settings: settings)
            }
    }
    */

    /// 转写当前音频文件
    /// - Parameter path: 音频文件路径
    func transcribeCurrentFile(
        url: URL, mediaType: MediaType, whisperKit: WhisperKit, settings: SettingsStore
    ) async throws {
        // 在限定作用域内加载并转换缓冲区
        Logging.debug("Loading audio file: \(url.path)")
        let loadingStart = Date()
        // 使用 async/await 和 autoreleasepool 优化内存管理，直接从 URL 加载音频数据
        // 创建一个“带检查的可抛出延续”，把“异步-回调”风格的代码包装成 Swift 原生 async/await 风格
        // 1. withCheckedThrowingContinuation 会立即返回一个 continuation 对象，并挂起当前 Task
        // 2. 我们在闭包里拿到这个 continuation，然后在后台线程去做真正的耗时工作（这里用 Task.detached）
        // 3. 耗时工作完成后，通过 continuation.resume(returning:) 把结果传回去，或者通过 resume(throwing:) 抛出错误
        // 4. 一旦 resume 被调用，被挂起的 Task 就会恢复，并把结果作为整行表达式的值返回给 audioFileSamples
        // 5. 如果 continuation 一直不 resume，Swift 运行时会在作用域结束时给出“未使用 continuation”的断言，帮助开发者发现遗漏
        let audioFileSamples: [Float] = try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let samples: [Float] = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
                let memoryBytes = samples.count * MemoryLayout<Float>.stride
                print(
                    "@@@DEBUG@: 加载音频文件 \(url.path) 成功，样本数: \(samples.count/1024)K，占用内存: \(memoryBytes / 1024)KB"
                )

                await MainActor.run {
                    continuation.resume(returning: samples)
                }
            }
        }

        // 如果之前没有计算总时长，这里作为备用方案
        if totalAudioDuration == 0 {
            totalAudioDuration = calculateAudioDuration(from: audioFileSamples).0
        }

        Logging.debug("Loaded audio file in \(Date().timeIntervalSince(loadingStart)) seconds")

        // 转写音频样本
        let transcription = try await transcribeAudioSamples(
            audioFileSamples,
            whisperKit: whisperKit,
            settings: settings,
        )

        // 在主线程更新UI相关状态
        //await MainActor.run {
        guard let segments = transcription?.segments else {
            return
        }

        // 更新转写进度
        updateTranscriptionProgress(with: segments)
        print(
            "@@@DEBUG: 转写进度更新3: \(String(format: "%.1f", self.transcriptionProgress * 100))%, URL: \(url.lastPathComponent)"
        )

        // 更新转写性能指标
        /*
        tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
        effectiveRealTimeFactor = transcription?.timings.realTimeFactor ?? 0
        effectiveSpeedFactor = transcription?.timings.speedFactor ?? 0
        currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
        firstTokenTime = transcription?.timings.firstTokenTime ?? 0
        modelLoadingTime = transcription?.timings.modelLoading ?? 0
        pipelineStart = transcription?.timings.pipelineStart ?? 0
        currentLag = transcription?.timings.decodingLoop ?? 0
        */
        // 更新已确认的片段
        confirmedSegments = segments.map { segment in
            AppTranscriptionSegment(
                start: Double(segment.start),
                end: Double(segment.end),
                text: segment.text
            )
        }
        print("@@@DEBUG: 更新已确认的片段数: \(confirmedSegments.count)")
        //}
    }

    /// 转写当前音频文件
    /// - Parameter path: 音频文件路径
    func transcribeCurrentFile_Video(
        file: SelectedAudioFile, whisperKit: WhisperKit, settings: SettingsStore
    ) async throws {
        // 在限定作用域内加载并转换缓冲区
        Logging.debug("Loading video file: \(file.fileUrl.path)")
        let loadingStart = Date()
        // 使用 async/await 和 autoreleasepool 优化内存管理，直接从 URL 加载音频数据
        // 创建一个“带检查的可抛出延续”，把“异步-回调”风格的代码包装成 Swift 原生 async/await 风格
        // 1. withCheckedThrowingContinuation 会立即返回一个 continuation 对象，并挂起当前 Task
        // 2. 我们在闭包里拿到这个 continuation，然后在后台线程去做真正的耗时工作（这里用 Task.detached）
        // 3. 耗时工作完成后，通过 continuation.resume(returning:) 把结果传回去，或者通过 resume(throwing:) 抛出错误
        // 4. 一旦 resume 被调用，被挂起的 Task 就会恢复，并把结果作为整行表达式的值返回给 audioFileSamples
        // 5. 如果 continuation 一直不 resume，Swift 运行时会在作用域结束时给出“未使用 continuation”的断言，帮助开发者发现遗漏
        let audioFileSamples: [Float] = try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                if file.mediaType == .audio || file.mediaType == .unknownAudio {
                    do {

                        let samples: [Float] = try AudioProcessor.loadAudioAsFloatArray(
                            fromPath: file.fileUrl.path)
                        let memoryBytes = samples.count * MemoryLayout<Float>.stride
                        print(
                            "@@@DEBUG@: 加载音频文件 \(file.fileUrl.path) 成功，样本数: \(samples.count/1024)K，占用内存: \(memoryBytes / 1024)KB"
                        )

                        await MainActor.run {
                            continuation.resume(returning: samples)
                        }
                    } catch {
                        await MainActor.run {
                            continuation.resume(throwing: error)
                        }
                    }
                } else if file.mediaType == .audioAndVideo || file.mediaType == .unknownVideo {
                    do {
                        let samples: [Float] = try await VideoExtractor.extractAudioData(
                            from: file.fileUrl)
                        await MainActor.run {
                            continuation.resume(returning: samples)
                        }
                    } catch {
                        await MainActor.run {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    await MainActor.run {
                        continuation.resume(
                            throwing: NSError(domain: "InvalidMediaType", code: 0, userInfo: nil))
                    }
                }
            }
        }

        // 如果之前没有计算总时长，这里作为备用方案
        if totalAudioDuration == 0 {
            totalAudioDuration = calculateAudioDuration(from: audioFileSamples).0
        }

        Logging.debug("Loaded audio file in \(Date().timeIntervalSince(loadingStart)) seconds")

        // 转写音频样本
        let transcription = try await transcribeAudioSamples(
            audioFileSamples,
            whisperKit: whisperKit,
            settings: settings,
        )

        // 在主线程更新UI相关状态
        //await MainActor.run {
        guard let segments = transcription?.segments else {
            return
        }

        // 更新转写进度
        updateTranscriptionProgress(with: segments)
        print(
            "@@@DEBUG: 转写进度更新3: \(String(format: "%.1f", self.transcriptionProgress * 100))%, URL: \(file.fileUrl.lastPathComponent)"
        )

        // 更新转写性能指标
        /*
        tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
        effectiveRealTimeFactor = transcription?.timings.realTimeFactor ?? 0
        effectiveSpeedFactor = transcription?.timings.speedFactor ?? 0
        currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
        firstTokenTime = transcription?.timings.firstTokenTime ?? 0
        modelLoadingTime = transcription?.timings.modelLoading ?? 0
        pipelineStart = transcription?.timings.pipelineStart ?? 0
        currentLag = transcription?.timings.decodingLoop ?? 0
        */
        // 更新已确认的片段
        confirmedSegments = segments.map { segment in
            AppTranscriptionSegment(
                start: Double(segment.start),
                end: Double(segment.end),
                text: segment.text
            )
        }
        print("@@@DEBUG: 更新已确认的片段数: \(confirmedSegments.count)")
        //}
    }

    /// 转写音频样本
    /// - Parameter samples: 音频样本数组
    /// - Returns: 转写结果
    func transcribeAudioSamples(
        _ samples: [Float], whisperKit: WhisperKit?, settings: SettingsStore
    ) async throws -> TranscriptionResult? {
        print(
            "@@DEBUG: transcribeAudioSamples开始执行，whisperKit状态: \(whisperKit != nil ? "已初始化" : "nil")"
        )
        guard let whisperKit = whisperKit else {
            print("@@DEBUG: transcribeAudioSamples中whisperKit为nil，返回nil")
            return nil
        }

        let lastConfirmedSegmentEndSeconds: Float = 0  // 最后确认段结束时间
        let sampleLength: Double = 224  // 样本长度
        let concurrentWorkerCount: Double = 4  // 并发工作线程数
        let chunkingStrategy: ChunkingStrategy = .vad  // 分块策略
        let compressionCheckWindow: Double = 60  // 压缩检查窗口
        // 从 settings 中获取配置参数
        let selectedLanguage = settings.selectedLanguage
        let selectedTask = settings.selectedTask
        let temperatureStart = settings.temperatureStart
        let fallbackCount = settings.fallbackCount
        let enablePromptPrefill = settings.enablePromptPrefill
        let enableCachePrefill = settings.enableCachePrefill
        let enableSpecialCharacters = settings.enableSpecialCharacters
        let enableTimestamps = settings.enableTimestamps

        // 获取语言代码和任务类型
        let languageCode = Constants.languages[
            selectedLanguage, default: Constants.defaultLanguageCode]
        let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
        let seekClip: [Float] = [lastConfirmedSegmentEndSeconds]

        let promptText = settings.initialPrompts.first(where: {
            ($0.languageCode ?? "").lowercased() == selectedLanguage.lowercased()
        })?.prompt ?? ""

        // 配置解码选项
        let options = DecodingOptions(
            verbose: true,
            task: task,
            language: languageCode,
            temperature: Float(temperatureStart),
            temperatureFallbackCount: fallbackCount,
            sampleLength: Int(sampleLength),
            usePrefillPrompt: enablePromptPrefill,
            usePrefillCache: enableCachePrefill,
            skipSpecialTokens: !enableSpecialCharacters,
            withoutTimestamps: !enableTimestamps,
            wordTimestamps: false,
            clipTimestamps: seekClip,
            promptTokens: whisperKit.tokenizer?.encode(text: promptText),
            concurrentWorkerCount: Int(concurrentWorkerCount),
            chunkingStrategy: chunkingStrategy
        )

        // 解码回调函数，用于处理转写进度
        let decodingCallback: @Sendable (TranscriptionProgress) -> Bool? = { progress in
            if Task.isCancelled {
                Logging.debug("Decoding callback received cancellation; early stop requested.")
                return false
            }

            Task { @MainActor in
                if self.transcriptionProgress == 0.0 {
                    self.transcriptionProgress = 0.005
                }

                if self.transcriptionProgress < 0.015 {
                    self.transcriptionProgress = self.transcriptionProgress + 0.001
                }

                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                let chunkId = self.isStreamMode ? 0 : progress.windowId

                if let previousChunkText = self.currentChunks[chunkId] {
                    if progress.text.count >= previousChunkText.count {
                        self.currentChunks[chunkId] = progress.text
                    } else if fallbacks == self.currentFallbacks && self.isStreamMode {
                        let baseText = previousChunkText
                        self.currentChunks[chunkId] = baseText + progress.text
                    } else {
                        self.currentChunks[chunkId] = progress.text
                        print("检测到回退: \(fallbacks)")
                    }
                }

                self.currentChunks[chunkId] = progress.text

                let joinedChunks = self.currentChunks
                    .sorted(by: { $0.key < $1.key })
                    .map { $0.value }
                    .joined(separator: "\n")

                self.currentText = joinedChunks
                self.currentFallbacks = fallbacks
            }

            let currentTokens = progress.tokens
            let checkWindow = Int(compressionCheckWindow)
            if currentTokens.count > checkWindow {
                let checkTokens: [Int] = currentTokens.suffix(checkWindow)
                let compressionRatio = TextUtilities.compressionRatio(of: checkTokens)
                if compressionRatio > options.compressionRatioThreshold! {
                    Logging.debug("Early stopping due to compression threshold")
                    return false
                }
            }
            if progress.avgLogprob! < options.logProbThreshold! {
                Logging.debug("Early stopping due to logprob threshold")
                return false
            }
            return nil
        }

        // 片段发现回调
        let segmentCallback: SegmentDiscoveryCallback = { segments in
            // 使用实际的片段信息更新进度，确保在主线程执行
            Task { @MainActor in
                self.updateTranscriptionProgress(with: segments)
                print(
                    "@@@DEBUG: 转写进度更新0: 发现 \(segments.count) 个片段，进度: \(String(format: "%.1f", self.transcriptionProgress * 100))%"
                )
            }
        }

        whisperKit.segmentDiscoveryCallback = segmentCallback

        // 执行转写
        let transcriptionResults: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: decodingCallback
        )

        // 合并转写结果
        let mergedResults = TranscriptionUtilities.mergeTranscriptionResults(transcriptionResults)

        // 最终更新进度
        updateTranscriptionProgress(with: mergedResults.segments)
        print(
            "@@@DEBUG: 转写进度更新2: 合并 \(mergedResults.segments.count) 个片段，进度: \(String(format: "%.1f", self.transcriptionProgress * 100))%"
        )
        return mergedResults
    }

    func cancelTranscription() {

        transcribeTask?.cancel()
        // 停止计时器
        timerStop()

        isTranscribing = false
        transcriptionProgress = 0.0
        currentText = ""
        confirmedSegments.removeAll()
        currentChunks.removeAll()
    }

    private func transcriptionOptions(from settings: SettingsStore, promptTokens: [Int])
        -> DecodingOptions
    {
        var options = DecodingOptions()
        options.task = settings.selectedTask == "transcribe" ? .transcribe : .translate
        options.language = settings.selectedLanguage
        options.temperature = Float(settings.temperatureStart)
        options.temperatureIncrementOnFallback = 0.2
        options.temperatureFallbackCount = Int(settings.fallbackCount)
        // 不需要设置prompt，因为DecodingOptions类型没有这个属性
        options.promptTokens = promptTokens
        options.usePrefillPrompt = settings.enablePromptPrefill
        //options.skipSpecialTokens = !settings.enableSpecialCharacters
        options.skipSpecialTokens = false
        options.withoutTimestamps = !settings.enableTimestamps
        options.wordTimestamps = settings.enableEagerDecoding
        return options
    }

    private func decodeAudio(from audioFile: AVAudioFile) throws -> AVAudioPCMBuffer {
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(WhisperKit.sampleRate),
                channels: 1,
                interleaved: false)
        else {
            throw AudioDecodingError.invalidPCMFormat
        }

        let frameCount = AVAudioFrameCount(
            (Double(audioFile.length) / audioFile.processingFormat.sampleRate)
                * targetFormat.sampleRate)

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
        else {
            throw AudioDecodingError.bufferCreationFailed
        }

        guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: targetFormat)
        else {
            throw AudioDecodingError.converterCreationFailed
        }

        var error: NSError?
        converter.convert(to: pcmBuffer, error: &error) { inNumPackets, outStatus in
            let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(inNumPackets))
            do {
                guard let buffer = buffer else { throw AudioDecodingError.noAudioData }
                try audioFile.read(into: buffer, frameCount: AVAudioFrameCount(inNumPackets))
                outStatus.pointee = .haveData
                return buffer
            } catch {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if let error = error {
            throw error
        }

        return pcmBuffer
    }
}

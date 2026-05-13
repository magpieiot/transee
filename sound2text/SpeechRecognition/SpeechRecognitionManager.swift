//
//  SpeechRecognitionManager.swift
//  sound2text
//
//  Created by Deepmind Antigravity on 2026/01/30.
//

import Foundation
import Speech
import AVFoundation

/// 语音识别状态
public enum SpeechRecognitionState {
    case idle
    case recording
    case processing
    case completed
    case error(Error)
}

enum SpeechRecognizerError: LocalizedError {
    case noPermission                   // 003
    case internalServiceError           // 001
    case networkFailed                  // 002
    case onDeviceNotAvailable           // 1700
    case noSpeechDetected               // 203
    case modelDownloading               // 1110
    case recognitionForbidden           // 1107
    case hardwareBusy
    case unknown(Error)
    
    init(_ error: Error) {
        let nsError = error as NSError
        
        // 处理 Speech 框架底层错误 (kAFAssistantErrorDomain)
        if nsError.domain == "kAFAssistantErrorDomain" {
            switch nsError.code {
            case 203: self = .noSpeechDetected
            case 1110: self = .modelDownloading
            case 1700: self = .onDeviceNotAvailable
            case 1107: self = .recognitionForbidden
            default: self = .unknown(error)
            }
            return
        }
        
        self = .unknown(error)
    }

    var errorDescription: String? {
        switch self {
        case .noPermission: return "请在设置中开启语音识别权限"
        case .internalServiceError: return "语音识别服务异常，请稍后重试"
        case .networkFailed: return "网络连接异常，请重试"
        case .onDeviceNotAvailable: return "该设备不支持离线识别"
        case .noSpeechDetected: return "未检测到语音输入"
        case .modelDownloading: return "正在准备本地语言包..."
        case .recognitionForbidden: return "识别被拒绝。短时间内请求次数过多，触发限流策略（Quota）。"
        case .hardwareBusy: return "麦克风被占用，请关闭其他通话"
        case .unknown(let error): return "识别出错: \(error.localizedDescription)"
        }
    }
}

/// Apple 语音识别管理类
/// 负责处理 SFSpeechRecognizer 的初始化、设置、语言管理、文件识别和实时语音识别。
@MainActor
public class SpeechRecognitionManager: NSObject, ObservableObject, @preconcurrency SFSpeechRecognizerDelegate {
    
    // MARK: - Published Properties for UI
    
    /// 当前识别出的文本内容
    @Published public var transcribedText: String = ""
    
    /// 识别状态
    @Published public var state: SpeechRecognitionState = .idle
    
    /// 是否正在录音/识别
    @Published public var isRecording: Bool = false
    
    /// 是否有识别权限
    @Published public var isAuthorized: Bool = false
    
    /// 当前使用的语言环境
    @Published public var currentLocale: Locale
    
    /// 支持的所有语言环境列表
    @Published public var supportedLocales: [Locale] = []
    
    /// 识别进度 (0.0 - 1.0)
    @Published public var progress: Double = 0.0
    
    /// 最后的错误信息
    @Published public var lastError: Error?
    
    // MARK: - Private Properties
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // MARK: - Callbacks
    
    /// 音频数据回调 (用于波形显示)
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    /// 实时识别内容回调 (当前文本, 是否最终结果)
    var onRealTimeTranscription: ((String, Bool) -> Void)?
    
    /// 文件识别进度回调 (当前文本, 进度 0.0-1.0)
    var onFileTranscriptionUpdate: ((String, Double) -> Void)?
    
    /// 识别完成回调 (最终文本)
    var onCompletion: ((String) -> Void)?
    
    /// 错误回调
    var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    public override init() {
        // 默认使用系统当前语言，如果不支持则回退到英语
        let locale = Locale.current
        self.currentLocale = locale
        super.init()
        
        setupSpeechRecognizer(locale: locale)
        PermissionManager.shared.checkSpeechRecognitionStatus()
        PermissionManager.shared.checkMicrophoneStatus()
        isAuthorized = PermissionManager.shared.speechRecognitionStatus == .granted
            && PermissionManager.shared.microphoneStatus == .granted
        refreshSupportedLocales()
    }
    
    /// 初始化并设置语言
    public init(locale: Locale) {
        self.currentLocale = locale
        super.init()
        
        setupSpeechRecognizer(locale: locale)
        PermissionManager.shared.checkSpeechRecognitionStatus()
        PermissionManager.shared.checkMicrophoneStatus()
        isAuthorized = PermissionManager.shared.speechRecognitionStatus == .granted
            && PermissionManager.shared.microphoneStatus == .granted
        refreshSupportedLocales()
    }
    
    private func setupSpeechRecognizer(locale: Locale) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.delegate = self
    }
    
    /// 请求语音识别权限
    public func requestAuthorization() {
        Task { @MainActor in
            let speechGranted = await PermissionManager.shared.requestSpeechRecognitionPermission()
            let micGranted = await PermissionManager.shared.requestMicrophonePermission()
            isAuthorized = speechGranted && micGranted
        }
    }
    
    // MARK: - Language Management
    
    /// 获取支持的语言列表
    public func refreshSupportedLocales() {
        self.supportedLocales = SFSpeechRecognizer.supportedLocales().sorted {
            $0.identifier < $1.identifier
        }
    }
    
    /// 设置识别语言
    /// - Parameter locale: 目标语言环境
    public func setLanguage(locale: Locale) {
        guard supportedLocales.contains(locale) else {
            print("Language \(locale.identifier) not supported.")
            return
        }
        
        // 如果正在识别，先停止
        if isRecording {
            stopRecording()
        }
        
        self.currentLocale = locale
        setupSpeechRecognizer(locale: locale)
    }

    /// 设置是否在设备上运行识别
    /// - Parameter isOnDevice: 是否在设备上运行识别（默认 true）
    public func setOnDeviceRecognition(isOnDevice: Bool = true) throws {
        guard let recognizer = speechRecognizer else {
            throw SpeechRecognizerError.internalServiceError
        }
        recognizer.supportsOnDeviceRecognition = isOnDevice 
    }   
    
    /// 是否支持在设备上运行识别
    public var isSupportsOnDeviceRecognition: Bool {
        return speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
    
    // MARK: - Real-time Speech Recognition
    
    /// 开始实时语音识别（通过麦克风）
    public func startRecording() throws {
        // 取消当前已有的任务
        cancelRecording()
        
        state = .recording
        isRecording = true
        lastError = nil
        transcribedText = ""
        
        // 配置 Audio Session (macOS 上通常不需要像 iOS 那样配置 AVAudioSession，但需要确保 Input Node 可用)
        // 在 macOS 上，AVAudioEngine 使用默认输入设备
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecognizerError.internalServiceError
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognizerError.internalServiceError
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // 保持设备常亮或处理中断等逻辑（iOS特有，macOS可忽略）
        
        let inputNode = audioEngine.inputNode
        
        // 开始识别任务
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // 回调
                self.onRealTimeTranscription?(self.transcribedText, isFinal)
                
                if isFinal {
                    self.state = .completed
                    self.isRecording = false
                    self.onCompletion?(self.transcribedText)
                }
            }
            
            if let error = error {
                self.stopAudioEngine()
                self.isRecording = false
                let mappedError = SpeechRecognizerError(error)
                self.state = .error(mappedError)
                self.lastError = mappedError
                self.onError?(mappedError)
            }
        }
        
        // 配置音频输入格式
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            self.onAudioBuffer?(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    /// 停止录音并结束识别
    public func stopRecording() {
        stopAudioEngine()
        recognitionRequest?.endAudio()
        isRecording = false
        state = .idle
    }
    
    /// 取消录音
    public func cancelRecording() {
        stopAudioEngine()
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        state = .idle
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    // MARK: - File Recognition
    
    /// 识别音频文件
    /// - Parameter url: 音频文件 URL
    public func transcribeFile(url: URL) {
        cancelRecording() // 确保没有正在进行的任务
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            let error = SpeechRecognizerError.internalServiceError
            self.lastError = error
            self.onError?(error)
            return
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = NSError(domain: "SpeechRecognitionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "File does not exist."])
            self.lastError = error
            self.onError?(error)
            return
        }
        
        state = .processing
        lastError = nil
        transcribedText = ""
        progress = 0.0
        
        Task { @MainActor in
            // 获取音频时长用于计算进度
            let asset = AVURLAsset(url: url)
            let duration: Double
            if #available(macOS 13.0, *) {
                do {
                    duration = try await CMTimeGetSeconds(asset.load(.duration))
                } catch {
                    print("Error loading duration: \(error)")
                    duration = 0
                }
            } else {
                duration = CMTimeGetSeconds(asset.duration)
            }
            
            startFileRecognition(url: url, duration: duration, recognizer: recognizer)
        }
    }

    // 
    private func startFileRecognition(url: URL, duration: Double, recognizer: SFSpeechRecognizer) {
        // 创建 URL 识别请求
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true 
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
                
                // 计算进度
                if duration > 0 {
                    let currentTimestamp = result.bestTranscription.segments.last?.timestamp ?? 0
                    let currentDuration = result.bestTranscription.segments.last?.duration ?? 0
                    let calculatedProgress = min((currentTimestamp + currentDuration) / duration, 1.0)
                     self.progress = calculatedProgress
                }
                 
                // 回调进度和文本
                self.onFileTranscriptionUpdate?(self.transcribedText, self.progress)
                
                if result.isFinal {
                    self.state = .completed
                    self.progress = 1.0
                    self.onCompletion?(self.transcribedText)
                    self.recognitionTask = nil
                }
            }
            
            if let error = error {
                let mappedError = SpeechRecognizerError(error)
                self.state = .error(mappedError)
                self.lastError = mappedError
                self.onError?(mappedError)
                self.recognitionTask = nil
            }
        }
    }
    
    // MARK: - SFSpeechRecognizerDelegate
    
    public nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else { return }
        Task { @MainActor [weak self] in
            self?.isRecording = false
            self?.state = .idle
        }
    }
}

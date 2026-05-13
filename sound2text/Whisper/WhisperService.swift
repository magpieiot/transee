//
//  WhisperService.swift
//  sound2text
//
//  Created by gavanwang on 8/22/25.
//

//
//  WhisperService.swift
//  sound2text
//
//  Created by gavanwang on 8/22/25.
//

//
//  WhisperService.swift
//  sound2text
//
//  Created by gavanwang on 8/22/25.
//
//  Refactored by Gemini for improved structure and maintainability.
//

import AVFoundation
import Combine
import CoreAudio
import CoreML
import CoreMedia
import SwiftUI
@preconcurrency import WhisperKit

extension Progress: @unchecked Sendable {}

// 自定义错误类型，用于更清晰地指示可能出现的问题
enum AudioTrackDurationError: Error, LocalizedError {
    case invalidVideoURL
    case fileDoesNotExist
    case assetLoadingFailed(Error)
    case noAudioTrackFound
    case invalidAudioDuration

    var errorDescription: String? {
        switch self {
        case .invalidVideoURL:
            return "提供的视频文件 URL 无效。"
        case .fileDoesNotExist:
            return "指定路径的视频文件不存在。"
        case .assetLoadingFailed(let error):
            return "加载视频资产轨道失败: \(error.localizedDescription)"
        case .noAudioTrackFound:
            return "视频文件中未找到音频轨道。"
        case .invalidAudioDuration:
            return "无法获取有效的音频时长。"
        }
    }
}

// MARK: - 辅助错误类型 (无变化)
enum AudioDecodingError: Error, LocalizedError {
    case invalidPCMFormat
    case bufferCreationFailed
    case noFloatChannelData
    case converterCreationFailed
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .invalidPCMFormat: return "Unable to create the required PCM audio format."
        case .bufferCreationFailed: return "Unable to create audio buffer."
        case .noFloatChannelData: return "Audio buffer does not contain float channel data."
        case .converterCreationFailed: return "Unable to create audio converter."
        case .noAudioData: return "No audio data after conversion."
        }
    }
}


// MARK: - 模型信息定义
// 建议: 为了便于更新，可以将此数据移至应用包内的JSON文件中，并在应用启动时加载。
struct WhisperModelInfo: Identifiable, Decodable, Equatable {
    let id = UUID()
    let name: String
    let estimatedDownloadSize: Double
    let estimatedSpeed: Int
    let estimatedAccuracy: Int
    let estimatedMemoryGB: Int
    let description: String?
    let trademark: String?
    let recommended: Bool?

    /// 用于展示的下载大小字符串（>1000MB 时按 GB 显示并保留 1 位小数）
    var estimatedDownloadSizeDisplay: String {
        guard estimatedDownloadSize >= 0 else { return "-" }
        if estimatedDownloadSize > 1000 {
            return String(format: "%.1f GB", estimatedDownloadSize / 1000.0)
        } else {
            return "\(Int(estimatedDownloadSize)) MB"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, estimatedDownloadSize, estimatedSpeed, estimatedAccuracy, estimatedMemoryGB,
            description, trademark, recommended
    }
}

let predefinedModels: [WhisperModelInfo] = [
    WhisperModelInfo(
        name: "openai_whisper-tiny", estimatedDownloadSize: 76.6, estimatedSpeed: 5,
        estimatedAccuracy: 1, estimatedMemoryGB: 1, description: "最小、最快，准确度一般", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-tiny.en", estimatedDownloadSize: 153, estimatedSpeed: 5,
        estimatedAccuracy: 1, estimatedMemoryGB: 1, description: "最小、最快，准确度一般", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-base", estimatedDownloadSize: 147, estimatedSpeed: 4,
        estimatedAccuracy: 2, estimatedMemoryGB: 2, description: "比 tiny 大，准确度更高", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-base.en", estimatedDownloadSize: 147, estimatedSpeed: 4,
        estimatedAccuracy: 2, estimatedMemoryGB: 2, description: "比 base 大，准确度更高", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-small", estimatedDownloadSize: 486, estimatedSpeed: 3,
        estimatedAccuracy: 3, estimatedMemoryGB: 3, description: "中等大小，平衡速度和准确度", trademark: "openai", recommended: true),
    WhisperModelInfo(
        name: "openai_whisper-small_216MB", estimatedDownloadSize: 217, estimatedSpeed: 3,
        estimatedAccuracy: 3, estimatedMemoryGB: 3, description: "中等大小，平衡速度和准确度", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-small.en", estimatedDownloadSize: 487, estimatedSpeed: 3,
        estimatedAccuracy: 3, estimatedMemoryGB: 3, description: "中等大小，平衡速度和准确度", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-small.en_217MB", estimatedDownloadSize: 218, estimatedSpeed: 3,
        estimatedAccuracy: 3, estimatedMemoryGB: 3, description: "中等大小，平衡速度和准确度", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-medium", estimatedDownloadSize: 1530, estimatedSpeed: 2,
        estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "更大、更慢，准确度较高", trademark: "openai", recommended: true),
    WhisperModelInfo(
        name: "openai_whisper-medium.en", estimatedDownloadSize: 1530, estimatedSpeed: 2,
        estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "更大、更慢，准确度较高", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v2", estimatedDownloadSize: 3090, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v2)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v2_949MB", estimatedDownloadSize: 952, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v2)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v2_turbo", estimatedDownloadSize: 3100, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v2)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v2_turbo_955MB", estimatedDownloadSize: 1050, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v2)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3", estimatedDownloadSize: 3090, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: true),
    WhisperModelInfo(
        name: "openai_whisper-large-v3-v20240930", estimatedDownloadSize: 1620, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3-v20240930_547MB", estimatedDownloadSize: 550,
        estimatedSpeed: 1, estimatedAccuracy: 5, estimatedMemoryGB: 5,
        description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3-v20240930_626MB", estimatedDownloadSize: 627,
        estimatedSpeed: 1, estimatedAccuracy: 5, estimatedMemoryGB: 5,
        description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3-v20240930_turbo", estimatedDownloadSize: 1640,
        estimatedSpeed: 1, estimatedAccuracy: 5, estimatedMemoryGB: 5,
        description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3-v20240930_turbo_632MB", estimatedDownloadSize: 646,
        estimatedSpeed: 1, estimatedAccuracy: 5, estimatedMemoryGB: 5,
        description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3_947MB", estimatedDownloadSize: 948, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: false),
    WhisperModelInfo(
        name: "openai_whisper-large-v3_turbo", estimatedDownloadSize: 3200, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: true),
    WhisperModelInfo(
        name: "openai_whisper-large-v3_turbo_954MB", estimatedDownloadSize: 1050, estimatedSpeed: 1,
        estimatedAccuracy: 5, estimatedMemoryGB: 5, description: "最大、最慢，最高准确度 (v3)", trademark: "openai", recommended: true),
    WhisperModelInfo(
        name: "distil-whisper_distil-large-v3", estimatedDownloadSize: 1510, estimatedSpeed: 2,
        estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "更大、更慢，准确度较高", trademark: "distil", recommended: false),
    WhisperModelInfo(
        name: "distil-whisper_distil-large-v3_594MB", estimatedDownloadSize: 595, estimatedSpeed: 2,
        estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "更大、更慢，准确度较高", trademark: "distil", recommended: false),
    WhisperModelInfo(
        name: "distil-whisper_distil-large-v3_turbo", estimatedDownloadSize: 1530,
        estimatedSpeed: 2, estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "更大、更慢，准确度较高", trademark: "distil", recommended: false),
    WhisperModelInfo(
        name: "distil-whisper_distil-large-v3_turbo_600MB", estimatedDownloadSize: 607,
        estimatedSpeed: 2, estimatedAccuracy: 4, estimatedMemoryGB: 4, description: "中等、更慢，准确度较高", trademark: "distil", recommended: false),
    WhisperModelInfo(
        name: "Apple Speech Recognizer", estimatedDownloadSize: -1,
        estimatedSpeed: 5, estimatedAccuracy: 3, estimatedMemoryGB: -1, description: "中等、更慢，准确度较高", trademark: "apple", recommended: false),
]

// MARK: - 配置存储 (SettingsStore)
// 集中管理所有通过 @AppStorage 持久化的用户设置
class SettingsStore: ObservableObject {

    // 推荐模型
    @AppStorage("defaultModel") var defaultModel: String = WhisperKit.recommendedModels().default {
        willSet { objectWillChange.send() }
    }
    // 用户手动选择的模型
    @AppStorage("selectedModel") var selectedModel: String = "" {
        willSet { objectWillChange.send() }
    }

    // 用户手动选择的语言
    @AppStorage("selectedLanguage") var selectedLanguage: String = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("selectedTask") var selectedTask: String = "transcribe" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("repoName") var repoName: String = DefaultValueWhisperSetting.repoName {
        willSet { objectWillChange.send() }
    }

    // 功能开关配置
    @AppStorage("enableTimestamps") var enableTimestamps: Bool = DefaultValueWhisperSetting.enableTimestamps {
        willSet { objectWillChange.send() }
    }  // 启用时间戳
    @AppStorage("enablePromptPrefill") var enablePromptPrefill: Bool = DefaultValueWhisperSetting.enablePromptPrefill {
        willSet { objectWillChange.send() }
    }  // 启用提示预填充
    @AppStorage("enableCachePrefill") var enableCachePrefill: Bool = DefaultValueWhisperSetting.enableCachePrefill {
        willSet { objectWillChange.send() }
    }  // 启用缓存预填充
    @AppStorage("enableSpecialCharacters") var enableSpecialCharacters: Bool = DefaultValueWhisperSetting.enableSpecialCharacters {
        willSet { objectWillChange.send() }
    }  // 启用特殊字符
    @AppStorage("enableEagerDecoding") var enableEagerDecoding: Bool = DefaultValueWhisperSetting.enableEagerDecoding {
        willSet { objectWillChange.send() }
    }  // 启用紧急解码
    @AppStorage("enableDecoderPreview") var enableDecoderPreview: Bool = DefaultValueWhisperSetting.enableDecoderPreview {
        willSet { objectWillChange.send() }
    }  // 启用解码器预览

    @AppStorage("temperatureStart") var temperatureStart: Double = DefaultValueWhisperSetting.temperatureStart {
        willSet { objectWillChange.send() }
    }
    @AppStorage("fallbackCount") var fallbackCount: Int = DefaultValueWhisperSetting.fallbackCount {
        willSet { objectWillChange.send() }
    }
    @AppStorage("compressionCheckWindow") var compressionCheckWindow: Double = DefaultValueWhisperSetting.compressionCheckWindow {
        willSet { objectWillChange.send() }
    }
    @AppStorage("sampleLength") var sampleLength: Int = DefaultValueWhisperSetting.sampleLength {
        willSet { objectWillChange.send() }
    }
    @AppStorage("silenceThreshold") var silenceThreshold: Double = DefaultValueWhisperSetting.silenceThreshold {
        willSet { objectWillChange.send() }
    }
    @AppStorage("initialPrompts") var initialPromptsData: Data = (try? JSONEncoder().encode(DefaultValueWhisperSetting.initialPrompts)) ?? Data() {
        willSet { objectWillChange.send() }
    }

    var initialPrompts: [PreDefinedPrompt] {
        get {
            guard let prompts = try? JSONDecoder().decode([PreDefinedPrompt].self, from: initialPromptsData) else {
                return DefaultValueWhisperSetting.initialPrompts
            }
            return prompts
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                initialPromptsData = data
            }
        }
    }
    @AppStorage("realtimeDelayInterval") var realtimeDelayInterval: Double = DefaultValueWhisperSetting.realtimeDelayInterval {
        willSet { objectWillChange.send() }
    }
    @AppStorage("useVAD") var useVAD: Bool = true  // 使用语音活动检测
    @AppStorage("tokenConfirmationsNeeded") var tokenConfirmationsNeeded: Int = DefaultValueWhisperSetting.tokenConfirmationsNeeded {
        willSet { objectWillChange.send() }
    }  // 所需令牌确认数
    @AppStorage("concurrentWorkerCount") var concurrentWorkerCount: Int = DefaultValueWhisperSetting.concurrentWorkerCount {
        willSet { objectWillChange.send() }
    }  // 并发工作线程数
    @AppStorage("chunkingStrategy") var chunkingStrategy: ChunkingStrategy = DefaultValueWhisperSetting.chunkingStrategy {
        willSet { objectWillChange.send() }
    }  // 分块策略
    @AppStorage("encoderComputeUnits") var encoderComputeUnits: MLComputeUnits = DefaultValueWhisperSetting.encoderComputeUnits {
        willSet { objectWillChange.send() }
    }
    @AppStorage("decoderComputeUnits") var decoderComputeUnits: MLComputeUnits = DefaultValueWhisperSetting.decoderComputeUnits {
        willSet { objectWillChange.send() }
    }

    @AppStorage("downloadedModels") var downloadedModels: Data = Data() {
        willSet { objectWillChange.send() }
    }

    var downloadedModelsArray: [String: Int] {
        get {
            (try? JSONDecoder().decode([String: Int].self, from: downloadedModels)) ?? [:]
        }
        set {
            downloadedModels = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    #if os(macOS)
        @AppStorage("selectedAudioInput") var selectedAudioInput: String = "No Audio Input" {
            willSet { objectWillChange.send() }
        }
    #endif
}

// MARK: - 模型管理器 (ModelManager)
// 负责模型的下载、加载、状态管理和查询
@MainActor
final class ModelManager: ObservableObject, @unchecked Sendable {
    @Published var modelState: ModelState = .unloaded
    @Published var loadingProgressValue: Float = 0.0
    @Published var availableModels: [String] = []
    @Published var localModels: [String] = []
    @Published var recommendedModels: [String] = []
    @Published var availableLanguages: [String] = []
    @Published var errorMessage: String? = nil

    private var whisperKit: WhisperKit?
    private var audioProcessor: AudioProcessor?
    private let modelStoragePath = "huggingface/models/argmaxinc/whisperkit-coreml"

    // 获取 WhisperKit 实例
    func getWhisperKit() -> WhisperKit? {
        guard modelState == .loaded else { return nil }
        return whisperKit
    }

    // 获取模型存储路径
    func getModelStoragePath() -> String {
        return modelStoragePath
    }

    private func expectedDownloadBytes(for modelName: String) -> Int64? {
        guard let info = predefinedModels.first(where: { $0.name == modelName }) else {
            return nil
        }
        guard info.estimatedDownloadSize > 0 else {
            return nil
        }
        return Int64(info.estimatedDownloadSize * 1_000_000)
    }

    private func directoryFileSizeBytes(at folderURL: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    // 内部使用的本地模型发现逻辑
    private func discoverLocalModels() {
        print("@@@DEBUG: Discovering Local Models...")
        guard let documents = getDocumentsDirectoryURL() else {
            print("Unable to access the Documents directory.")
            return
        }

        let modelPath = documents.appendingPathComponent(modelStoragePath).path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("模型存储路径不存在: \(modelPath)")
            return
        }

        do {
            let downloadedModels = try FileManager.default.contentsOfDirectory(atPath: modelPath)
            // Modify: 20260407
            let formattedModels = ModelUtilities.formatModelFiles(downloadedModels)         //WhisperKit.formatModelFiles(downloadedModels)

            var newLocalModels: [String] = []
            for model in formattedModels {
                let fullPath = (modelPath as NSString).appendingPathComponent(model)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    // 只要文件夹存在且被记录在 AppStorage 中，就认为是已下载
                    if SettingsStore().downloadedModelsArray.keys.contains(model) {
                        newLocalModels.append(model)
                    }
                }
            }
            self.localModels = newLocalModels.filter { $0.contains("openai") }
            print("@@@DEBUG: Discovered Local Models: \(self.localModels)")
        } catch {
            print("枚举本地模型时出错: \(error.localizedDescription)")
        }
    }

    // 刷新可用模型列表
    // 包括本地模型和远程模型
    func fetchModels() {
        print("@@@DEBUG: Fetch Models ... ...")

        // 先进行本地扫描
        discoverLocalModels()

        // 更新 availableModels
        var updatedAvailableModels = [SettingsStore().defaultModel].filter { $0.contains("openai") }
        for model in self.localModels where !updatedAvailableModels.contains(model) {
            updatedAvailableModels.append(model)
        }
        self.availableModels = updatedAvailableModels

        // 异步获取远程模型列表
        Task {
            let remoteModels = await WhisperKit.recommendedRemoteModels()
            // 过滤推荐模型
            self.recommendedModels = remoteModels.supported.filter { modelName in
                modelName.contains("openai") &&
                (predefinedModels.first(where: { $0.name == modelName })?.recommended ?? false)
            }
            
            // 确保 availableModels 包含所有符合条件的预定义模型
            var allModels = predefinedModels.map { $0.name }.filter { $0.contains("openai") }
            
            // 如果有本地模型不在预定义列表中，也加上
            for model in self.localModels where !allModels.contains(model) {
                allModels.append(model)
            }
            
            self.availableModels = allModels
            print("@@@DEBUG: available Models updated: \(availableModels)")
        }
    }

    // 加载模型
    // 如果模型不在本地，则进行下载
    func loadModel(
        named modelName: String, from repo: String, computeOptions: ModelComputeOptions,
        redownload: Bool = false
    ) async {
        print("@@@DEBUG: Begin Loading Model: \(modelName)")
        guard modelState != .loading, modelState != .downloading else {
            print("模型已在加载中。")
            return
        }

        // 在加载前确保本地列表是最新的
        discoverLocalModels()

        modelState = .loading
        loadingProgressValue = 0.0
        whisperKit = nil

        do {
            // 查找或下载模型
            let modelFolder = try await findOrDownloadModel(modelName, from: repo, redownload: redownload)
            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: computeOptions,
                verbose: true,
                logLevel: .debug
            )

            let loadedKit = try await WhisperKit(config)
            modelState = .prewarming
            loadingProgressValue = max(loadingProgressValue, 0.2)
            do {
                try await loadedKit.prewarmModels()
                modelState = .prewarmed
                loadingProgressValue = max(loadingProgressValue, 0.6)
            } catch {
                print("预热模型失败: \(error.localizedDescription)")
                modelState = .unloaded
            }

            do {
                modelState = .loading
                try await loadedKit.loadModels()
            } catch {
                print("加载模型失败2: \(error.localizedDescription)")
                modelState = .unloaded
            }

            whisperKit = loadedKit
            if !localModels.contains(modelName) {
                localModels.append(modelName)
            }

            availableLanguages = Constants.languages.map { $0.key }.sorted()
            loadingProgressValue = 1.0
            modelState = .loaded

        } catch {
            let errorDescription = error.localizedDescription
            if errorDescription.contains("timed out") || errorDescription.contains("connection lost") || (error as NSError).code == NSURLErrorTimedOut || (error as NSError).code == NSURLErrorNotConnectedToInternet {
                print("@@@ERROR0: 网络无响应或连接中断。加载模型 \(modelName) 失败: \(errorDescription)")
                self.errorMessage = "Network connection failed. Please check your network settings."
            } else {
                print("加载模型失败1: \(modelName), Error: \(errorDescription)")
                self.errorMessage = errorDescription
            }

            if redownload {
                print("尝试重新下载...")
                await loadModel(
                    named: modelName, from: repo, computeOptions: computeOptions, redownload: true)
            } else {
                modelState = .unloaded
            }
        }
    }

    // 下载模型
    // 如果模型不在本地，则进行下载
    func downloadModel(modelName: String, repo: String) async {
        do {
            let downloadModelUrl = try await findOrDownloadModel(modelName, from: repo, redownload: true)
            print("@@@DEBUG: 模型 \(modelName) 下载完成, 路径: \(downloadModelUrl.path)")
        } catch {
            let errorDescription = error.localizedDescription
            if errorDescription.contains("timed out") || errorDescription.contains("connection lost") || (error as NSError).code == NSURLErrorTimedOut || (error as NSError).code == NSURLErrorNotConnectedToInternet {
                print("@@@ERROR1: 网络无响应。下载模型 \(modelName) 失败: \(errorDescription)")
                self.errorMessage = "Network connection failed. Please check your network settings."
            } else {
                print("下载模型失败: \(errorDescription)")
                self.errorMessage = errorDescription
            }
            self.modelState = .unloaded
        }
    }

    // 查找或下载模型
    // 如果模型不在本地，则进行下载
    private func findOrDownloadModel(_ modelName: String, from repo: String, redownload: Bool)
        async throws -> URL
    {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelFolderURL = documentsURL.appendingPathComponent(modelStoragePath).appendingPathComponent(modelName)

        // 检查本地文件系统是否确实存在该模型文件夹
        let modelExistsOnDisk = FileManager.default.fileExists(atPath: modelFolderURL.path)

        // 如果非强制重新下载，且本地已存在或被记录，则直接返回本地路径
        if !redownload {
            if modelExistsOnDisk && (localModels.contains(modelName) || SettingsStore().downloadedModelsArray.keys.contains(modelName)) {
                print("模型 \(modelName) 已存在于本地: \(modelFolderURL.path)，跳过下载。")
                return modelFolderURL
            }
        }

        print("正在开始下载（或重新下载）模型: \(modelName)...")
        modelState = .downloading
        self.loadingProgressValue = 0.0

        let downloadModelUrl = try await Task.detached { [modelName, repo] in
            try await WhisperKit.download(variant: modelName, from: repo) { @Sendable progress in
                let fraction = Float(progress.fractionCompleted)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.loadingProgressValue = fraction
                }
            }
        }.value

        let actualBytes = try directoryFileSizeBytes(at: downloadModelUrl)
        if let expectedBytes = expectedDownloadBytes(for: modelName) {
            let minimumBytes = Int64(Double(expectedBytes) * 0.8)
            if actualBytes < minimumBytes {
                SettingsStore().downloadedModelsArray.removeValue(forKey: modelName)
                modelState = .unloaded
                throw NSError(
                    domain: "ModelDownload",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "下载文件大小校验失败：expected≈\(expectedBytes) bytes, actual=\(actualBytes) bytes"
                    ]
                )
            }
        }

        modelState = .downloaded
        SettingsStore().downloadedModelsArray[modelName] = Int(actualBytes)
        print("@@@DEBUG: 模型 \(modelName) 下载完成, 路径: \(downloadModelUrl.path), size: \(actualBytes) bytes")
        return downloadModelUrl
    }

    func importLocalModel() async {
        // 搜索本地模型存储路径，导入已下载模型
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else {
            print("无法访问 Documents 目录")
            return
        }
        let modelDir = documents
            .appendingPathComponent(modelStoragePath)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            print("模型存储目录不存在：\(modelDir.path)")
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelDir,
                                                                       includingPropertiesForKeys: nil)
            var foundModels: [String] = []
            for item in contents where item.hasDirectoryPath {
                let modelName = item.lastPathComponent
                // 仅保留含 openai 的目录
                if modelName.contains("openai") {
                    foundModels.append(modelName)
                }
            }
            // 去重并排序
            foundModels = Array(Set(foundModels)).sorted()

            // 更新内存与持久化记录
            await MainActor.run {
                self.localModels = foundModels
                var downloadedDict = SettingsStore().downloadedModelsArray
                for name in foundModels {
                    // 若之前未记录，写入 0 表示已存在
                    if downloadedDict[name] == nil {
                        downloadedDict[name] = 0
                    }
                }
                SettingsStore().downloadedModelsArray = downloadedDict
                print("@@@DEBUG: 本地模型导入完成，共 \(foundModels.count) 个：\(foundModels)")
            }
        } catch {
            print("枚举本地模型失败：\(error.localizedDescription)")
        }
    }

    // 删除本地模型
    func deleteModel(_ modelName: String) {
        print("@@@DEBUG: Deleting Model: \(modelName)")

        // 1. 获取模型文件夹路径
        guard let documents = getDocumentsDirectoryURL() else {
            print("Unable to access the Documents directory.")
            return
        }
        let modelPath = documents.appendingPathComponent(modelStoragePath).appendingPathComponent(modelName)

        // 2. 删除文件
        do {
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
                print("Deleted model files at: \(modelPath.path)")
            } else {
                print("Model path not found: \(modelPath.path)")
            }
        } catch {
            print("Error deleting model files: \(error.localizedDescription)")
            return
        }

        // 3. 更新内存中的列表
        if let index = localModels.firstIndex(of: modelName) {
            localModels.remove(at: index)
        }

        // 4. 更新持久化存储
        var downloadedDict = SettingsStore().downloadedModelsArray
        downloadedDict.removeValue(forKey: modelName)
        SettingsStore().downloadedModelsArray = downloadedDict

        // 5. 重新刷新可用模型列表
        fetchModels()
    }

    func getEstimatedDownloadSizeString(_ modelInfo: WhisperModelInfo) -> String {
        // 计算并返回估计下载大小字符串
        let estimatedSize = modelInfo.estimatedDownloadSize
        let estimatedSizeString = estimatedSize > 1000
            ? "\(estimatedSize / 1000.0) GB"
            : "\(Int(estimatedSize)) MB"
        return estimatedSizeString
    }
}

// MARK: - 主服务外观 (WhisperService)
// 作为主外观，提供对所有服务的统一访问点
@MainActor
class WhisperService: ObservableObject {
    @Published var settings: SettingsStore
    @Published var modelManager: ModelManager
    @Published var transcriptionEngine: FileTranscriptionEngine
    @Published var liveTranscriptionEngine: LiveTranscriptionEngine

    // 用于存储订阅的取消令牌
    private var cancellables = Set<AnyCancellable>()

    init() {
        //let settings = SettingsStore()
        //let modelManager = ModelManager()
        //let transcriptionEngine = TranscriptionEngine()
        //let liveTranscriptionEngine = LiveTranscriptionEngine()

        self.settings = SettingsStore()
        self.modelManager = ModelManager()
        self.transcriptionEngine = FileTranscriptionEngine()
        self.liveTranscriptionEngine = LiveTranscriptionEngine()
        
        // 设置变化通知转发
        setupChangeForwarding()
        //Task {
            //print("@@@DEBUG: WhisperService init & loadSelectedModel")
        //    print("@@@DEBUG: WhisperService init & loadSelectedModel, settings.defaultModel: \(settings.defaultModel)")
            //await self.loadSelectedModel()
        //}
    }

    // 设置子对象变化通知的转发
    private func setupChangeForwarding() {
        // 转发 settings 的变化
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 转发 modelManager 的变化
        modelManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 转发 transcriptionEngine 的变化
        transcriptionEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 转发 liveTranscriptionEngine 的变化
        liveTranscriptionEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // 加载用户选择的模型
    func loadSelectedModel() async {
        let computeOptions = ModelComputeOptions(
            audioEncoderCompute: settings.encoderComputeUnits,
            textDecoderCompute: settings.decoderComputeUnits
        )
        await modelManager.loadModel(
            named: settings.selectedModel,
            from: settings.repoName,
            computeOptions: computeOptions
        )
    }

    func getSelectedModel() -> String {
        return settings.selectedModel
    }

    func getSelectedLanguage() -> String {
        return settings.selectedLanguage
    }

    // 开始转写文件
    func transcribeFile(at file: SelectedAudioFile) async {
        guard let whisperKit = modelManager.getWhisperKit() else {
            transcriptionEngine.currentText = "模型未加载。请先选择并加载一个模型。"
            return
        }
        // 初始化转写引擎
        transcriptionEngine.resetState(whisperKit: whisperKit, settings: settings)
        // 等待转写完成
        transcriptionEngine.transcribeFile(at: file, whisperKit: whisperKit, settings: settings)
        //print("transcriptionEngine.currentText: \(transcriptionEngine.currentText)")
    }

    // 开始转写实时音频
    func transcribeLiveMic() async {

        guard let whisperKit = modelManager.getWhisperKit() else { return }
        liveTranscriptionEngine.startRecording(true, whisperKit: whisperKit, settings: settings)
    }

    // 停止实时转写
    func stopLiveTranscribing() async {
        guard let whisperKit = modelManager.getWhisperKit() else { return }
        liveTranscriptionEngine.stopRecording(true, whisperKit: whisperKit, settings: settings)
    }

    // 重置转写状态
    func resetTranscriptionState() {
        guard let whisperKit = modelManager.getWhisperKit() else {
            transcriptionEngine.currentText = "模型未加载。请先选择并加载一个模型。"
            return
        }
        transcriptionEngine.cancelTranscription()
        whisperKit.clearState()
    }
}

/*

*/

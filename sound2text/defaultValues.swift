//
//  defaultValues.swift
//  transee
//
//  Created by gavanwang on 2026/2/9.
//

import Foundation
import WhisperKit
import CoreML



// 导出格式
enum ExportFormat: String {
    case txt = "TXT"
    case srt = "SRT"
    case ass = "ASS"
    case json = "JSON"
} 

// 默认值设置
struct DefaultValueSettings {
    static let launchAtLogin: Bool = true  // 是否在登录时启动
}

struct PreDefinedPrompt: Codable, RawRepresentable {
    var prompt: String?
    var languageCode: String?           // 语言代码，标准: 语言-国家（如 "zh-CN"）

    enum CodingKeys: String, CodingKey {
        case prompt
        case languageCode
    }

    public init(prompt: String? = nil, languageCode: String? = nil) {
        self.prompt = prompt
        self.languageCode = languageCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        self.languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
    }

    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(PreDefinedPrompt.self, from: data)
        else {
            return nil
        }
        self.prompt = result.prompt
        self.languageCode = result.languageCode
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }
}
// = "以下是中文简体普通话，使用标点符号。"
//  = "zh-CN"

struct DefaultValueWhisperSetting {
    static let enableTimestamps: Bool = true  // 是否启用时间戳
    static let enablePromptPrefill: Bool = true  // 是否使用提示预填
    static let enableCachePrefill: Bool = true  // 是否启用缓存预热
    static let enableSpecialCharacters: Bool = false  // 是否允许特殊字符
    static let enableEagerDecoding: Bool = true  // 是否启用抢先解码
    static let enableDecoderPreview: Bool = true  // 是否启用解码器预览
    static let temperatureStart: Double = 0.0  // 起始温度，用于采样
    static let fallbackCount: Int = 5  // 回退尝试次数
    static let repoName: String = "argmaxinc/whisperkit-coreml"  // 模型仓库名称
    static let compressionCheckWindow: Double = 60  // 压缩检查窗口
    static let sampleLength: Int = 224  // 样本长度
    static let silenceThreshold: Double = 0.3  // 静音阈值
    static let initialPrompts: [PreDefinedPrompt] = [
        PreDefinedPrompt(prompt: "以下是中文简体普通话，使用标点符号。", languageCode: "chinese"),
        PreDefinedPrompt(prompt: "以下是中文繁體，使用標點符號。", languageCode: "cantonese"),
        PreDefinedPrompt(prompt: "The following is English, using punctuation.", languageCode: "english"),
        PreDefinedPrompt(prompt: "El siguiente es español, usando puntuación.", languageCode: "spanish"),
        PreDefinedPrompt(prompt: "Le prochain est le français, en utilisant la ponctuation.", languageCode: "french"),
        PreDefinedPrompt(prompt: "Il seguente è italiano, usando la punteggiatura.", languageCode: "italian"),
        PreDefinedPrompt(prompt: "다음은 한국어입니다. 구두점을 사용합니다.", languageCode: "korean"),
        PreDefinedPrompt(prompt: "次は日本語です。句読点を使用します。", languageCode: "japanese"),
    ]  // 初始提示文本
    static let realtimeDelayInterval: Double = 2.0  // 实时延迟间隔
    static let maxBufferSize: Double = 1024 * 1024 * 10  // 最大缓存大小
    static let tokenConfirmationsNeeded: Int = 3  // 确认令牌数
    static let concurrentWorkerCount: Int = 2  // 并发工作线程数
    static let chunkingStrategy: ChunkingStrategy = .vad // 分块策略
    static let encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine  // 编码器计算单元数
    static let decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine  // 解码器计算单元数

}


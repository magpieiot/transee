//
//  VideoExtractor.swift
//  sound2text
//
//  Created by gavanwang on 9/24/25.
//

import AVFoundation
import Foundation
import WhisperKit

/// 视频音频提取工具
class VideoExtractor {

    enum ExtractorError: Error {
        case noAudioTrack
        case readerSetupFailed
        case readingFailed
    }

    /// 从视频文件中提取音频数据
    ///
    /// - Parameter videoURL: 本地视频文件的 URL
    /// - Returns: 音频数据 [Float]，格式为 16kHz 单声道，与 AudioProcessor.loadAudioAsFloatArray 格式一致
    static func extractAudioData(from videoURL: URL) async throws -> [Float] {
        // 1. 创建 AVAudioFile 用于读取视频中的音频轨道
        // AVAudioFile 可以直接读取支持的视频容器中的音频（如 mp4, mov）
        let audioFile = try AVAudioFile(forReading: videoURL)
        let processingFormat = audioFile.processingFormat

        // 2. 定义目标格式 (Whisper 需要 16kHz, 单声道, Float32)
        // 使用 WhisperKit.sampleRate 确保采样率一致 (通常是 16000)
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(WhisperKit.sampleRate),
                channels: 1,
                interleaved: false)
        else {
            throw NSError(
                domain: "VideoAudioExtractor", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建目标音频格式 (16kHz, Mono, Float32)"])
        }

        // 3. 创建音频转换器
        guard let converter = AVAudioConverter(from: processingFormat, to: targetFormat) else {
            throw NSError(
                domain: "VideoAudioExtractor", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法创建音频转换器"])
        }

        // 4. 计算目标帧数
        // 估算转换后的总帧数
        let ratio = targetFormat.sampleRate / processingFormat.sampleRate
        let estimatedFrameCount = AVAudioFrameCount(Double(audioFile.length) * ratio)
        // 稍微增加一点缓冲以防估算偏差
        let bufferCapacity = estimatedFrameCount + AVAudioFrameCount(targetFormat.sampleRate * 2)  // +2秒缓冲

        // 5. 创建输出缓冲区
        guard
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: bufferCapacity)
        else {
            throw NSError(
                domain: "VideoAudioExtractor", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法创建输出缓冲区"])
        }

        // 6. 执行转换
        var conversionError: NSError?

        // 转换器的输入回调块
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            // 创建临时输入缓冲区用于读取文件
            guard
                let inputBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: inNumPackets)
            else {
                outStatus.pointee = .noDataNow
                return nil
            }

            do {
                // 从文件中读取数据
                try audioFile.read(into: inputBuffer)

                if inputBuffer.frameLength == 0 {
                    // 文件读取完毕
                    outStatus.pointee = .endOfStream
                    return nil
                } else {
                    // 成功读取数据
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
            } catch {
                print("VideoAudioExtractor: 读取音频文件出错: \(error)")
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

        if let error = conversionError {
            throw error
        }

        // 7. 提取 Float 数据
        guard let channelData = outputBuffer.floatChannelData else {
            throw NSError(
                domain: "VideoAudioExtractor", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "无法获取音频 Float 数据"])
        }

        // 获取第一个通道的数据（因为是单声道）
        let channelPointer = channelData.pointee
        let frameLength = Int(outputBuffer.frameLength)

        // 转换为 Swift 数组
        let floatArray = Array(UnsafeBufferPointer(start: channelPointer, count: frameLength))

        return floatArray
    }
}

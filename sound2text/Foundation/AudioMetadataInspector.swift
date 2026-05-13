//
//  AudioMetadataInspector.swift
//  sound2text
//
//  Created by gavanwang on 9/1/25.
//


import Foundation
import AVFoundation
import UniformTypeIdentifiers
import CoreMedia
import WhisperKit

// 定义输出枚举
enum MediaType {
    case audio
    case video
    case audioAndVideo // 同时包含音频和视频
    case unknownAudio        // 无法识别或不包含任何可识别的音频轨道
    case unknownVideo        // 无法识别或不包含任何可识别的视频轨道
    case notMediaFile       // 文件不存在或不是一个媒体文件
    case invalidType
}

struct AudioTags {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var genre: String?
    var comment: String?
    var trackNumber: String?
    var artworkData: Data?
    
    var isEmpty: Bool {
        return [title, artist, album, year, genre, comment, trackNumber].allSatisfy { ($0 ?? "").isEmpty } && artworkData == nil
    }
}

struct AudioMetadata {
    var url: URL
    var container: String?
    var durationSeconds: Double?
    var codec: String?
    var averageBitRateBps: Double?
    var sampleRateHz: Double?
    var channelCount: Int?
    var bitDepthPerChannel: Int?
    var fileSizeBytes: Int?
    var tags: AudioTags
    var id3Raw: [String: String]
}

enum AudioMetadataError: Error {
    case invalidURL
    case noAudioTrack
}

final class AudioMetadataInspector {
    func inspect(url: URL) async throws -> AudioMetadata {
        // AVAsset
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        // 加载基本信息
        let duration = try? await asset.load(.duration)
        let seconds = duration.map { CMTimeGetSeconds($0) }
        
        // 容器 / 扩展名 / UTI
        var container: String? = url.pathExtension.uppercased()
        if let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            container = container ?? typeIdentifier
        }
        
        // 文件大小
        var fileSizeBytes: Int? = nil
        if url.isFileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSizeBytes = size
        }
        
        // 解析音频轨道
        let tracks = try await asset.load(.tracks)
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard let audioTrack = audioTracks.first else {
            // 可能是纯容器无轨，或者格式不被识别
            throw AudioMetadataError.noAudioTrack
        }
        
        // 码率（估算）
        let estimatedRate = try? await audioTrack.load(.estimatedDataRate)
        let averageBitRateBps: Double? = estimatedRate.map { $0 > 0 ? Double($0) : nil } ?? nil
        
        // 编码、采样率、声道、位深（来自格式描述）
        var codec: String? = nil
        var sampleRateHz: Double? = nil
        var channelCount: Int? = nil
        var bitDepthPerChannel: Int? = nil
        
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        for fd in formatDescriptions {
            let desc = fd
            if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                let asbd = asbdPtr.pointee
                // codec
                codec = codecLabel(from: asbd.mFormatID)
                // sample rate / channel
                if asbd.mSampleRate > 0 { sampleRateHz = asbd.mSampleRate }
                if asbd.mChannelsPerFrame > 0 { channelCount = Int(asbd.mChannelsPerFrame) }
                if asbd.mBitsPerChannel > 0 { bitDepthPerChannel = Int(asbd.mBitsPerChannel) }
                break
            } else {
                // 非 PCM 的编码可尝试通过媒体子类型 fourCC
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                codec = codec ?? fourCCToString(subType)
            }
        }
        
        // 元数据（ID3 / iTunes / Common）
        var tags = AudioTags()
        var id3Raw: [String: String] = [:]
        
        // Common Metadata
        for item in try await asset.load(.commonMetadata) {
            guard let key = item.commonKey?.rawValue else { continue }
            let valA = (try? await item.load(.stringValue)) ?? ""
            let valN = (try? await item.load(.numberValue))?.stringValue ?? ""
            let val = valA.isEmpty ? valN : valA
            if val.isEmpty { continue }
            switch key {
                case AVMetadataKey.commonKeyTitle.rawValue:
                    tags.title = tags.title ?? val
                case AVMetadataKey.commonKeyArtist.rawValue:
                    tags.artist = tags.artist ?? val
                case AVMetadataKey.commonKeyAlbumName.rawValue:
                    tags.album = tags.album ?? val
                case AVMetadataKey.commonKeyCreationDate.rawValue:
                    if tags.year == nil { tags.year = val }
                case AVMetadataKey.commonKeyType.rawValue:
                    // 一些文件会把类型或流派放在这里
                    tags.genre = tags.genre ?? val
                default:
                    break
            }
        }
        
        // 具体格式的 metadata（ID3 / iTunes）
        for format in try await asset.load(.availableMetadataFormats) {
            let items = try await asset.loadMetadata(for: format)
            for item in items {
                let keyName = (item.identifier?.rawValue) ?? (item.commonKey?.rawValue) ?? "unknown"
                let strA = try await item.load(.stringValue) ?? ""
                let strN = (try? await item.load(.numberValue))?.stringValue ?? ""
                let str = strA.isEmpty ? strN : strA
                if !str.isEmpty {
                    id3Raw[keyName] = str
                }
                
                // ID3 / iTunes 常见映射
                if tags.title == nil, matches(keyName, anyOf: ["id3/TIT2", "iTunesMetadataKeySongName"]) { tags.title = str }
                if tags.artist == nil, matches(keyName, anyOf: ["id3/TPE1", "iTunesMetadataKeyArtist"]) { tags.artist = str }
                if tags.album == nil, matches(keyName, anyOf: ["id3/TALB", "iTunesMetadataKeyAlbum"]) { tags.album = str }
                if tags.year == nil, matches(keyName, anyOf: ["id3/TYER", "id3/TDRC", "iTunesMetadataKeyReleaseDate"]) { tags.year = str }
                if tags.genre == nil, matches(keyName, anyOf: ["id3/TCON", "iTunesMetadataKeyUserGenre", "iTunesMetadataKeyPredefinedGenre"]) { tags.genre = str }
                if tags.comment == nil, matches(keyName, anyOf: ["id3/COMM", "iTunesMetadataKeyUserComment"]) { tags.comment = str }
                if tags.trackNumber == nil, matches(keyName, anyOf: ["id3/TRCK", "iTunesMetadataKeyTrackNumber"]) { tags.trackNumber = str }
                
                // 封面
                if tags.artworkData == nil {
                    if let data = await extractArtworkData(from: item) {
                        tags.artworkData = data
                    }
                }
            }
        }
        
        return AudioMetadata(
            url: url,
            container: container,
            durationSeconds: seconds,
            codec: codec,
            averageBitRateBps: averageBitRateBps,
            sampleRateHz: sampleRateHz,
            channelCount: channelCount,
            bitDepthPerChannel: bitDepthPerChannel,
            fileSizeBytes: fileSizeBytes,
            tags: tags,
            id3Raw: id3Raw
        )
    }

    // MARK: - Helpers

    private func matches(_ key: String, anyOf candidates: [String]) -> Bool {
        candidates.contains { key.localizedCaseInsensitiveContains($0) }
    }

    private func extractArtworkData(from item: AVMetadataItem) async -> Data? {
        if let data = try? await item.load(.dataValue) { return data }
        if let raw = try? await item.load(.value) {
            if let data = raw as? Data { return data }
            if let dict = raw as? [String: Any], let data = dict["data"] as? Data { return data }
        }
        return nil
    }

    private func fourCCToString(_ code: FourCharCode) -> String {
        let be = CFSwapInt32HostToBig(code)
        let bytes: [UInt8] = [
            UInt8((be >> 24) & 0xFF),
            UInt8((be >> 16) & 0xFF),
            UInt8((be >> 8) & 0xFF),
            UInt8(be & 0xFF)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? bytes.map { String(format: "%c", $0) }.joined()
    }

    private func codecLabel(from formatID: AudioFormatID) -> String {
        // 常见格式映射，覆盖主流编码
        let map: [AudioFormatID: String] = [
            kAudioFormatLinearPCM: "PCM",
            kAudioFormatAppleLossless: "ALAC",
            kAudioFormatMPEG4AAC: "AAC",
            kAudioFormatMPEGLayer3: "MP3",
            kAudioFormatMPEG4AAC_HE: "AAC-HE",
            kAudioFormatMPEG4AAC_ELD: "AAC-ELD",
            kAudioFormatFLAC: "FLAC",
            kAudioFormatOpus: "Opus"
        ]
        return map[formatID] ?? fourCCToString(formatID)
    }
}

// 格式化时长为 HH:MM:SS 或 MM:SS
func formatDuration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite else { return "-" }
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}

// 格式化码率为 kbps
func formatBitRate(_ bps: Double?) -> String {
    guard let bps, bps > 0 else { return "-" }
    let kbps = bps / 1000.0
    return String(format: "%.0f kbps", kbps)
}
    
// 格式化采样率为 kHz 或 Hz
func formatSampleRate(_ hz: Double?) -> String {
    guard let hz, hz > 0 else { return "-" }
    if hz >= 1000 {
        return String(format: "%.1f kHz", hz / 1000.0)
    } else {
        return String(format: "%.0f Hz", hz)
    }
}


/// 从音频文件URL计算总时长
    /// - Parameter url: 音频文件URL
    /// - Returns: 音频时长（秒）
func calculateAudioDuration(from url: URL) async -> (Double, Double) {
    do {
        let audioFile = try AVAudioFile(forReading: url)
        let sampleRate = audioFile.fileFormat.sampleRate
        let frameCount = audioFile.length
        print("@@@DEBUG: 音频文件: 采样率: \(sampleRate), 时长: \(Double(frameCount) / sampleRate)")
        return (Double(frameCount) / sampleRate, sampleRate)
    } catch {
        print("无法获取音频文件时长: \(error)")
        return (0.0, 0.0)
    }
}

/// 计算音频文件总时长
/// - Parameter audioSamples: 音频样本数组
/// - Returns: 音频时长（秒）
func calculateAudioDuration(from audioSamples: [Float]) -> (Double, Double) {
    return (Double(audioSamples.count) / Double(WhisperKit.sampleRate), Double(WhisperKit.sampleRate))
}


/// 计算视频文件的时间长度（秒）
/// - Parameter url: 视频文件 URL
/// - Returns: 视频时长（秒）
func calculateAudioTrackDuration(from url: URL) async throws -> (Double, Double) {
    // 1. 验证 URL 是否是本地文件 URL
    guard url.isFileURL else {
        throw AudioTrackDurationError.invalidVideoURL
    }
    
    // 2. 检查文件是否存在
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AudioTrackDurationError.fileDoesNotExist
    }
    let asset = AVURLAsset(url: url)
    // 3. 异步加载资产的 'tracks' 属性
    // 当 'tracks' 属性加载完成后，其内部的 AVAssetTrack 对象的 duration 属性也会被加载。
    do {
        _ = try await asset.load(.tracks)
    } catch {
        throw AudioTrackDurationError.assetLoadingFailed(error)
    }
    // 4. 查找音频轨道
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
        throw AudioTrackDurationError.noAudioTrackFound
    }
    
    // 5. 获取音频轨道的时长
    let audioDuration = try await audioTrack.load(.timeRange).duration
    
    // 6. 检查音频时长是否有效
    guard audioDuration.isValid && !audioDuration.isIndefinite && !audioDuration.isNegativeInfinity && !audioDuration.isPositiveInfinity else {
        throw AudioTrackDurationError.invalidAudioDuration
    }
    
    // 7. 将 CMTime 转换为秒
    let seconds = Double(audioDuration.value) / Double(audioDuration.timescale)
    // 8. 检查转换后的秒数是否有效
    guard seconds.isFinite else {
        throw AudioTrackDurationError.invalidAudioDuration
    }
    return (seconds, Double(audioDuration.timescale))
}


// 枚举当前系统的音频输入选项

func listAudioInputOptions() -> [String] {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    return session.availableInputs?.map { $0.portName } ?? []
    #elseif os(macOS)
    let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
    return discoverySession.devices.map { $0.localizedName }
    #else
    return []
    #endif
}



/// 判断指定 URL 的文件是音频文件、视频文件，还是两者皆有。
///
/// - Parameters:
///   - fileURL: 要检查的本地文件的 URL。
///
/// - Returns: 一个 `MediaType` 枚举值，表示文件的媒体类型。
///
/// - Throws: `Error` 如果在文件访问或资产加载过程中发生无法处理的错误。
func identifyMediaFileType(at fileURL: URL) async throws -> MediaType {
    let asset = AVURLAsset(url: fileURL)

    // 加载轨道列表
    do { 
        _ = try await asset.load(.tracks) 
    } catch {
        print("@@@DEBUG: Error loading asset tracks for \(fileURL.path): \(error.localizedDescription)")
        // 如果文件扩展名是音频格式，直接返回.audio
        if let typeID = try? fileURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let utType = UTType(typeID)
        {
            if utType.conforms(to: .audio) {
                return .unknownAudio
            }

            if utType.conforms(to: .movie) {
                return .unknownVideo
            }
        }
        return .invalidType
    }

    // 音频轨道是否存在
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let hasAudioTrack = !audioTracks.isEmpty

    // 视频轨道是否有效（过滤封面等非播放视频）
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    var hasValidVideoTrack = false
    for track in videoTracks {
        let size = (try? await track.load(.naturalSize)) ?? .zero
        let rate = (try? await track.load(.nominalFrameRate)) ?? 0
        let timeRange = (try? await track.load(.timeRange)) ?? .zero
        let duration = timeRange.duration.seconds
        if size.width > 0 && size.height > 0 && rate > 0 && duration > 0.01 {
            hasValidVideoTrack = true
            break
        }
    }

    // 基于 UTType 的回退判断（处理无轨但扩展名明确的情况）
    var isAudioUTI = false
    var isMovieUTI = false
    if let typeId = try? fileURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
       let uti = UTType(typeId) {
        isAudioUTI = uti.conforms(to: .audio)
        isMovieUTI = uti.conforms(to: .movie)
    }

    // 分类决策
    if hasAudioTrack && hasValidVideoTrack { return .audioAndVideo }
    if hasAudioTrack { return .audio }
    if hasValidVideoTrack { return .video }
    if isAudioUTI { return .unknownAudio }
    if isMovieUTI { return .video }
    return .invalidType
}

// 调试函数：获取文件的所有轨道信息
// 该函数用于异步加载指定 URL 文件的所有轨道信息，打印到控制台。
// 主要用于调试目的，帮助理解文件的媒体类型和时长。
func debugGetTracks(for url: URL) async {
    print("尝试加载文件: \(url.lastPathComponent)")
    
    // 1. 初始 URL 验证
    guard url.isFileURL else {
        print("错误: URL 不是本地文件 URL。")
        return
    }
    
    // 2. 文件存在性检查
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("错误: 文件不存在于路径: \(url.path)")
        return
    }
    let asset = AVURLAsset(url: url)
    do {
        // 尝试异步加载 .tracks 属性
        _ = try await asset.load(.tracks)
        print("成功加载 tracks 属性。文件似乎有效。")
        // 如果这里成功，你可以继续处理 tracks 信息
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for track in audioTracks {
            let rate = (try? await track.load(.nominalFrameRate)) ?? 0
            let timeRange = (try? await track.load(.timeRange)) ?? .zero
            let duration = timeRange.duration.seconds
            print("@@@DEBUG: 轨道类型: \(track.mediaType.rawValue), 时长: \(duration)秒, 帧率: \(rate)")
        }
    } catch {
        // 捕获错误并打印详细信息
        print("--- 捕获到加载轨道错误 ---")
        print("Localized Description: \(error.localizedDescription)") // 用户友好的错误信息
        print("Full Error: \(error)") // 完整的 Swift Error 对象
        if let nsError = error as NSError? {
            print("NSError Domain: \(nsError.domain)")
            print("NSError Code: \(nsError.code)")
            print("NSError UserInfo: \(nsError.userInfo)")
            // 特别关注 AVFoundation 相关的错误码
            if nsError.domain == AVFoundationErrorDomain {
                switch nsError.code {
                case AVError.fileFormatNotRecognized.rawValue:
                    print("AVFoundation Error: 文件格式无法识别。")
                case AVError.diskFull.rawValue:
                    print("AVFoundation Error: 磁盘已满。")
                case AVError.noLongerPlayable.rawValue:
                    print("AVFoundation Error: 内容不再可播放（可能是 DRM 或权限问题）。")
                case -11819: // 常见错误码，表示资产没有有效的段落（文件可能损坏）
                    print("AVFoundation Error: -11819 (assetHasNoValidMediaSegments) - 资产没有有效的段落（文件可能损坏）。")
                    print("AVFoundation Error: 资产没有有效的段落（文件可能损坏）。")
                case -11828: // 这是一个常见的错误码，通常表示无法打开
                    print("AVFoundation Error: -11828 (kFigMediaEditorError_CannotOpenAsset) - 无法打开资产。")
                case -11841: // Another common error code for unsupported content
                    print("AVFoundation Error: -11841 (AVErrorContentIsUnavailable) - 内容不可用或不支持。")
                default:
                    print("AVFoundation Error: 未知 AVError 代码 \(nsError.code)")
                }
            } else if nsError.domain == NSCocoaErrorDomain {
                 // 可能会有文件访问权限相关的错误
                if nsError.code == NSFileReadNoPermissionError {
                    print("Cocoa Error: 文件读取权限不足。")
                }
            }
        }
    }
}

/*
// MARK: - 使用示例 (如何在实际 App 中调用此函数)
import SwiftUI
import AppKit

struct FileTypeIdentifierView: View {
    @State private var statusMessage: String = "点击按钮选择文件..."
    @State private var identifiedType: MediaType?

    var body: some View {
        VStack(spacing: 20) {
            Text(statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()

            Button("选择文件并识别类型") {
                selectFileAndIdentifyType()
            }
            .buttonStyle(.borderedProminent)

            if let type = identifiedType {
                Text("识别到的文件类型: \(displayString(for: type))")
                    .font(.subheadline)
                    .padding(.top)
            }
        }
        .frame(minWidth: 400, minHeight: 250)
        .padding()
    }

    private func displayString(for type: MediaType) -> String {
        switch type {
        case .audio: return "纯音频文件"
        case .video: return "纯视频文件"
        case .audioAndVideo: return "音视频文件"
        case .unknown: return "未知媒体文件类型"
        case .notMediaFile: return "不是媒体文件或文件不存在"
        case .invalidURL: return "无效的 URL"
        }
    }

    private func selectFileAndIdentifyType() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // 允许选择所有文件，以便检查非媒体文件的情况
        // 如果只想选择媒体文件，可以设置 allowedContentTypes
        panel.allowedContentTypes = [.audio, .movie, .item]
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                Task {
                    await MainActor.run {
                        statusMessage = "正在识别文件 \(selectedURL.lastPathComponent) 的类型..."
                        identifiedType = nil
                    }
                    
                    do {
                        let type = try await identifyMediaFileType(at: selectedURL)
                        await MainActor.run {
                            identifiedType = type
                            statusMessage = "文件类型识别完成。"
                        }
                    } catch {
                        await MainActor.run {
                            statusMessage = "识别文件类型时发生错误: \(error.localizedDescription)"
                            identifiedType = nil
                        }
                    }
                }
            } else {
                statusMessage = "文件选择已取消。"
            }
        }
    }
}

// PreviewProvider for SwiftUI Canvas
struct FileTypeIdentifierView_Previews: PreviewProvider {
    static var previews: some View {
        FileTypeIdentifierView()
    }
}
*/

//  Subtitle.swift
//  sound2text
//
//  Created by gavanwang on 12/4/25.
//  Copyright © 2025 gavanwang. All rights reserved.
//

import Foundation
@preconcurrency import WhisperKit

// 生成纯 Text 格式的字幕
func makeText(from segments: [TranscriptionSegment], onProgress: (@Sendable (String, Double) -> Void)? = nil) async -> String {
    let totalRows = Double(segments.count)

    return await Task.detached(priority: .userInitiated) {
        var result = ""
        result.reserveCapacity(segments.count * 200) // 预分配内存，假设每行平均 100 字符
        for (index, segment) in segments.enumerated() {
            result.append(segment.text)
            result.append("\n")
            let progress = Double(index + 1) / totalRows
            if index % 10 == 0, let onProgress {
                onProgress(result, progress)
            }
        }
        return result
    }.value
}

// 生成 JSON 格式的字幕
// 仅导出 startTime, endTime, text 字段
func makeJSON(from segments: [TranscriptionSegment], onProgress: ((String) -> Void)? = nil) async -> String? {
    // 定义局部结构体以仅导出特定字段
    struct ExportRow: Encodable {
        let startTime: Double
        let endTime: Double
        let text: String
    }

    let encoder = JSONEncoder()
    // 可选：设置输出格式，使其可读性更高 (但会略微增加文件大小和编码时间)
    encoder.outputFormatting = .prettyPrinted
    // 可选：设置日期编码策略
    // 例如：将日期编码为 ISO 8601 字符串，这是常见的 Web API 格式
    encoder.dateEncodingStrategy = .iso8601
    do {
        let exportRows = segments.map { ExportRow(startTime: Double($0.start), endTime: Double($0.end), text: $0.text) }
        let jsonData = try encoder.encode(exportRows) // 核心转换，得到 Data 类型
        // 将 Data 转换为 String (如果需要 JSON 字符串)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("Successfully converted to JSON.")
            return jsonString
        } else {
            print("Error: Could not convert JSON Data to String.")
            return nil
        }
    } catch {
        print("Error encoding users array to JSON: \(error.localizedDescription)")
        return nil
    }
}


// 生成SRT格式的字幕
func makeSRT(from segments: [TranscriptionSegment], onProgress: (@Sendable (String) -> Void)? = nil) async -> String {
    await Task.detached(priority: .userInitiated) {
        var result = ""
        result.reserveCapacity(segments.count * 150) // 预分配内存
        
        for (index, segment) in segments.enumerated() {
            result.append("\(index + 1)\n")
            result.append("\(formatSmartTime(seconds: Double(segment.start), type: .forSrt)) --> \(formatSmartTime(seconds: Double(segment.end), type: .forSrt))\n")
            result.append("\(segment.text)\n\n")
            
            if index % 50 == 0, let onProgress {
                onProgress(result)
            }
        }
        if !result.isEmpty {
            result.removeLast()
        }
        return result
    }.value
}

// 生成ASS格式的字幕
func makeASS(from segments: [TranscriptionSegment], onProgress: (@Sendable (String) -> Void)? = nil) async -> String {
    await Task.detached(priority: .userInitiated) {
        var result = """
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,36,&H00FFFFFF,&H0000FFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

"""
        result.reserveCapacity(result.count + segments.count * 200)
        
        for (index, segment) in segments.enumerated() {
            let start = formatASSTime(seconds: Double(segment.start))
            let end = formatASSTime(seconds: Double(segment.end))
            let text = segment.text.contains("\n") ? segment.text.replacingOccurrences(of: "\n", with: "\\N") : segment.text
            
            result.append("Dialogue: 0,\(start),\(end),Default,,0,0,0,,\(text)\n")
            
            if index % 50 == 0, let onProgress {
                onProgress(result)
            }
        }
        
        return result
    }.value
}

// 格式化时间为ASS时间格式
func formatASSTime(seconds: Double) -> String {
    let total = Int(round(seconds * 100))
    let h = total / 360000
    let m = (total % 360000) / 6000
    let s = (total % 6000) / 100
    let cs = total % 100
    return String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
}

//
//  pasteboard.swift
//  sound2text
//
//  Created by gavanwang on 2025/12/9.
//

import Foundation
import AppKit

func copyToPasteboard(text: String) -> Bool {
    let pasteboard = NSPasteboard.general // 获取共享的通用剪贴板
    pasteboard.clearContents() // 清空剪贴板的现有内容 (推荐)
    // 尝试写入字符串内容
    if pasteboard.setString(text, forType: .string) {
        return true
        // 可以在这里添加一些视觉反馈，例如短暂的勾号图标或颜色变化
    } else {
        return false
    }
}


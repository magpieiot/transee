//
//  MacOSTrafficLightButton.swift
//  sound2text
//
//  Created by gavanwang on 8/25/25.
//

import SwiftUI
import AppKit

// 定义按钮类型
enum ButtonType {
    case close
    case minimize
    case maximize
}

struct MacOSTrafficLightButton: View {
    let type: ButtonType
    let action: () -> Void
    @State private var isHovering = false // 跟踪鼠标是否悬停
    var body: some View {
        Button(action: action) {
            ZStack {
                // 底层的圆形背景
                Circle()
                    .fill(backgroundColor(for: type))
                    .frame(width: 14, height: 14)
                // 悬停时显示的图标
                if isHovering {
                    Image(systemName: iconName(for: type))
                        //.resizable()
                        //.scaledToFit()
                        .frame(width: 10, height: 10) // 调整图标大小
                        .foregroundColor(iconColor(for: type)) // 图标颜色
                }
            }
        }
        .buttonStyle(.plain) // 关键：移除默认按钮样式
        .onHover { hovering in // ⭐ 鼠标悬停事件
            isHovering = hovering
        }
    }
    // 根据按钮类型返回背景颜色
    private func backgroundColor(for type: ButtonType) -> Color {
        switch type {
            case .close: return .red
            case .minimize: return .yellow
            case .maximize: return .green
        }
    }
    // 根据按钮类型返回 SFSymbol 名称
    private func iconName(for type: ButtonType) -> String {
        switch type {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .maximize: return "arrow.up.left.and.arrow.down.right" // 或 "plus.rectangle.fill"
        }
    }
    
    // 根据按钮类型返回图标颜色
    private func iconColor(for type: ButtonType) -> Color {
        // macOS 交通灯图标通常是黑色或深灰色, 除非在特定主题下
        return .black.opacity(0.8) 
        // 或者 Color.controlTextColor, Color.labelColor 等 AppKit 颜色
    }
}

// 扩展 Color 获取 macOS 窗口背景色 (需要 AppKit)
extension Color {
    static var windowBackground: Color {
        Color(NSColor.windowBackgroundColor)
    }
}

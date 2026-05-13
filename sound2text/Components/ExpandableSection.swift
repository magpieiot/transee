//
//  ExpandableSection.swift
//  TranSee
//
//  Created by gavanwang on 2026/3/5.
//
import SwiftUI

// MARK: - 可复用的 DisclosureGroup 组件
struct ExpandableSection<Content: View>: View {
    @Binding var isExpanded: Bool
    let title: String
    let icon: String?
    let subtitle: String?
    let showArrow: Bool
    let arrowPosition: ArrowPosition
    let content: Content
    
    enum ArrowPosition {
        case left, right, hidden
    }
    
    init(isExpanded: Binding<Bool>,
         title: String,
         icon: String? = nil,
         subtitle: String? = nil,
         showArrow: Bool = true,
         arrowPosition: ArrowPosition = .right,
         @ViewBuilder content: () -> Content) {
        self._isExpanded = isExpanded
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.showArrow = showArrow
        self.arrowPosition = arrowPosition
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    if arrowPosition == .left && showArrow {
                        arrowView
                    }
                    
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .frame(width: 30)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            //.font(.headline)
                            //.foregroundColor(.primary)
                        
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if arrowPosition == .right && showArrow {
                        arrowView
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "双击收起" : "双击展开")
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            
            if isExpanded {
                content
                    .padding(.top, 8)
                    .padding(.leading, icon != nil ? 42 : 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var arrowView: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.secondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

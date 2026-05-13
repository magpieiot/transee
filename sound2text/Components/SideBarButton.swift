//
//  SideBarButton.swift
//  sound2text
//
//  Created by gavanwang on 9/3/25.
//
import SwiftUI

// MARK: - 侧边栏按钮组件
struct SideBarButton: View {
    let title: String
    let icon: String?
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let height: CGFloat
    let alignment: Alignment
    let labelColor: Color
    let backgroundColor: Color
    let isActive: Bool
    let isLoading: Bool
    let isAvailable: Bool
    let action: () -> Void

    @State private var isHovering = false

    init(
        title: String, icon: String?, minWidth: CGFloat = 120, maxWidth: CGFloat = 160,
        height: CGFloat = 44, alignment: Alignment = .leading, labelColor: Color = .white,
        backgroundColor: Color = Color.accentBrandPrimary, isActive: Bool = false,
        isLoading: Bool = false, isAvailable: Bool = true, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
        self.alignment = alignment
        self.labelColor = labelColor
        self.backgroundColor = backgroundColor
        self.isActive = isActive
        self.isLoading = isLoading
        self.isAvailable = isAvailable
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center) {
                if alignment == .center || alignment == .trailing {
                    Spacer()
                }

                if isLoading {
                    ProgressView()
                        .foregroundColor(isActive ? labelColor : Color.secondary)
                        .frame(width: 20, height: 20)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(isActive ? labelColor : Color.secondary)
                            .frame(width: 24, height: 24)
                    }
                }
                Text(isLoading ? "Loading" : title)
                    .font(.body)
                    .foregroundColor(isActive ? labelColor : Color.secondary)

                if alignment == .center || alignment == .leading {
                    Spacer()
                }
            }
            .padding(getPadding(alignment).0, CGFloat(getPadding(alignment).1))
            .frame(height: height)
            .background(
                isActive
                    ? backgroundColor
                    : (isHovering ? Color.buttonHover : Color.sidebarBackground.opacity(0.1))
            )
            .foregroundColor(
                isActive ? .white : (isHovering ? Color.textSecondary : Color.textPrimary)
            )
            .cornerRadius(.infinity)
            .shadow(
                color: isActive ? backgroundColor.opacity(0.5) : .gray, 
                radius: isActive ? 8 : 0.1 
            )
        }
        .buttonStyle(isActive ? .borderless : .borderless)
        .frame(minWidth: minWidth, maxWidth: maxWidth)
        .disabled(isLoading || !isAvailable)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    private func getPadding(_ alignment: Alignment) -> (Edge.Set, Int) {
        switch alignment {
            case .center:
                if icon != nil {
                    return (.horizontal, 8)
                } else {
                    return (.trailing, 8)
                }
            case .leading:
                return (.horizontal, 8)
            case .trailing:
                return (.trailing, 8)
            default:
                return (.horizontal, 0)
        }

    }
}

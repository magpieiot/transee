//
//  RoundedBorderText.swift
//  sound2text
//
//  Created by gavanwang on 8/29/25.
//
import SwiftUI

// 圆角边框文本
struct RoundedBorderText: View {
    var text: String
    var textColor: Color = .primary // 文字颜色，默认使用系统主色
    var backgroundColor: Color = .primary.opacity(0.1) // 背景颜色，默认使用系统次色
    var borderColor: Color = .gray    // 边框颜色
    var borderWidth: CGFloat = 1      // 边框宽度
    var cornerRadius: CGFloat = 99    // 圆角半径
    var horizontalPadding: CGFloat = 4 // 水平内边距
    var verticalPadding: CGFloat = 2   // 垂直内边距
    var externalPadding: CGFloat = 0  // 外部边距
    var body: some View {
        VStack{
            Text(text)
                .font(.subheadline) // 字体大小
                .foregroundColor(textColor) // 文字颜色
                .padding(.horizontal, horizontalPadding) // 设置水平内边距
                .padding(.vertical, verticalPadding)   // 设置垂直内边距
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius) // 圆角矩形作为 Overlay
                        .stroke(borderColor, lineWidth: borderWidth) // 设置边框颜色和宽度
                )
        }
        .padding(externalPadding) // 设置外部边距
    }
}

// 圆角边框按钮
struct RoundedBorderButton: View {
    let text: String
    let textColor: Color = .white // 文字颜色，默认使用系统主色
    let backgroundColor: Color = .accentBrandPrimary
    let borderColor: Color = .black    // 边框颜色
    let borderWidth: CGFloat = 1      // 边框宽度
    let cornerRadius: CGFloat = 100    // 圆角半径
    let horizontalPadding: CGFloat = 8 // 水平内边距
    let verticalPadding: CGFloat = 4   // 垂直内边距
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack{
                Text(text)
                    .font(.subheadline) // 字体大小
                    .padding(.horizontal, horizontalPadding) // 设置水平内边距
                    .padding(.vertical, verticalPadding)   // 设置垂直内边距
                    .foregroundColor(textColor) // 文字颜色
                    .background(
                         RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: borderWidth) // 设置边框颜色和宽度
                            .fill(backgroundColor)
                         )
            }
            .padding(0)
        }
    }
}

struct RoundedBorderText_Previews: PreviewProvider {
    static var previews: some View {
        RoundedBorderText(text: "Default")
    }
}



struct RoundedBorderButton_Previews: PreviewProvider {
    static var previews: some View {
        RoundedBorderButton(text: "Default", action: {})
            .padding()
    }
}

//
//  RatingDotsView.swift
//  sound2text
//
//  Created by gavanwang on 8/29/25.
//

import SwiftUI

struct RatingDotsView: View {
    let rating: Int // 输入的度量值，范围 0-5
    
    // 初始化时确保 rating 在有效范围内
    init(rating: Int) {
        self.rating = max(0, min(5, rating)) // 将 rating 限制在 0-5 之间
    }

    var body: some View {
        HStack(spacing: 3) { // 使用 HStack 来水平排列五个点
            ForEach(0..<5) { index in // 循环五次，创建五个点
                Circle() // 每个点是一个圆形
                    .fill(index < rating ? Color.green : Color.gray.opacity(0.6)) // 根据 index 和 rating 决定颜色
                    .frame(width: 4, height: 4) // 设置点的大小
            }
        }
    }
}

// MARK: - Preview Provider
struct RatingView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Rating: 0")
            RatingDotsView(rating: 0) // 所有点都是灰色

            Text("Rating: 1")
            RatingDotsView(rating: 1) // 一个绿点，四个灰点

            Text("Rating: 2")
            RatingDotsView(rating: 2) // 两个绿点，三个灰点

            Text("Rating: 3")
            RatingDotsView(rating: 3) // 三个绿点，两个灰点

            Text("Rating: 4")
            RatingDotsView(rating: 4) // 四个绿点，一个灰点

            Text("Rating: 5")
            RatingDotsView(rating: 5) // 所有点都是绿色
            
            Text("Rating: 7 (超出范围，应显示5个绿点)")
            RatingDotsView(rating: 7) // 测试超出范围的输入
            
            Text("Rating: -1 (超出范围，应显示0个绿点)")
            RatingDotsView(rating: -1) // 测试超出范围的输入
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}


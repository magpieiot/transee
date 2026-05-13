import SwiftUI

struct LoadingRing: View {
    /// 圆环的大小（直径）
    var size: CGFloat = 50
    /// 圆环线条的宽度
    var lineWidth: CGFloat = 4
    /// 圆环的颜色
    var colors: [Color] = [.blue, .purple]

    @State private var isAnimating = false

    var body: some View {
        Circle()
            // 截取一部分圆弧，形成缺口，以便观察到旋转
            .trim(from: 0, to: 0.75)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: colors), center: .center, startAngle: .zero,
                    endAngle: .degrees(360)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                // 创建无限循环的旋转动画
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
            .background(Color.clear)  // 背景透明
    }
}

#Preview {
    ZStack {
        // 为了演示背景透明，给父视图加一个背景色
        Color.black.opacity(0.1)

        VStack(spacing: 20) {
            LoadingRing(size: 30, lineWidth: 3, colors: [.red, .orange])
            LoadingRing(size: 50, lineWidth: 5, colors: [.blue, .purple])
            LoadingRing(size: 80, lineWidth: 8, colors: [.green, .yellow])
        }
    }
}

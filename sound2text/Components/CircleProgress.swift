//
//  ContentView.swift
//  sound2text
//
//  Created by gavanwang on 9/12/25.
//

import SwiftUI
import AppKit

// 
struct CircleProgress: View {
    var thickness: CGFloat = 8.0
    var width: CGFloat = 40.0
    var startAngle = -90.0
    var backgroundColor: Color = Color.lightGrayBackground
    var foreGradient: Gradient = Gradient(colors: [.successGreen, .munsellBlue])
    var progressTextFontSize = 12.0
    var isProgressTextShow = true
    var progress: Double

    var body: some View {
        ZStack {

            // 外环
            Circle()
                .stroke(backgroundColor, lineWidth: thickness)

            // 内环
            RingShape(progress: progress, thickness: thickness)
                .fill(AngularGradient(gradient: foreGradient, center: .center, startAngle: .degrees(startAngle), endAngle: .degrees(360 * progress + startAngle)))
            
            Text("\(String(format: "%d", Int(progress*100.0+0.5)))")
                .font(.system(size: progressTextFontSize))
                .fontWeight(.regular)
        }
        .frame(width: width, height: width, alignment: .center)
        .animation(Animation.easeInOut(duration: 1.0),value: progress)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CircleProgress(thickness: 8.0, width: 32, progress: 0.155)
                .padding()
        }
    }
}

// 内环
struct RingShape: Shape {

    var progress: Double = 0.0
    var thickness: CGFloat = 8.0
    var startAngle: Double = -90.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {

        var path = Path()

        path.addArc(center: CGPoint(x: rect.width / 2.0, y: rect.height / 2.0), radius: min(rect.width, rect.height) / 2.0, startAngle: .degrees(startAngle), endAngle: .degrees(360 * progress + startAngle), clockwise: false)

        return path.strokedPath(.init(lineWidth: thickness, lineCap: .round))
    }
}

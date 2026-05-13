
import SwiftUI

struct LiveWaveformView: View {
    /// The stream of energy levels (amplitudes)
    var samples: [Float]
    /// Total duration of the audio represented by samples (in seconds)
    var totalDuration: Double
    
    // User Requirements:
    // - Height 64 (handled by modifier)
    // - Color Red
    // - 0.2s per grid (bar)
    // - Scroll Left
    
    private let barColor: Color = .red
    private let timePerBar: Double = 0.1 // 0.2s per bar
    
    // Visual configuration
    private let visualBarWidth: CGFloat = 4.0
    private let barSpacing: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            Canvas { context, size in
                // If no data, draw nothing
                guard !samples.isEmpty, totalDuration > 0 else {
                    return
                }
                
                // Calculate sample rate (samples per second)
                let sampleRate = Double(samples.count) / totalDuration
                
                // How many samples represent one 0.2s bar?
                let samplesPerBar = Int(sampleRate * timePerBar)
                // Avoid division by zero
                guard samplesPerBar > 0 else { return }
                
                let totalBarWidth = visualBarWidth + barSpacing
                
                // Calculate how many bars fit in the screen
                let distinctBarsOnScreen = Int(width / totalBarWidth) + 2 // +2 for buffer
                
                // Total logical bars available in data
                let totalDataBars = samples.count / samplesPerBar
                
                // We draw from the rightmost edge to the left
                // The newest data should be at the right side.
                // We iterate backwards from the latest chunk.
                
                let numBarsToDraw = min(distinctBarsOnScreen, totalDataBars)
                
                for i in 0..<numBarsToDraw {
                    // 0 is the newest bar
                    let chunkIndex = totalDataBars - 1 - i
                    if chunkIndex < 0 { break }
                    
                    let startSample = chunkIndex * samplesPerBar
                    let endSample = min(startSample + samplesPerBar, samples.count)
                    
                    if startSample >= endSample { continue }
                    
                    // Extract chunk and calculate magnitude (RMS)
                    let chunk = samples[startSample..<endSample]
                    let sumSquares = chunk.reduce(0) { $0 + $1 * $1 }
                    let rms = sqrt(sumSquares / Float(chunk.count))
                    
                    // Determine Height
                    // Scale factor: Tune this for visibility. 
                    // Assuming relativeEnergy is normalized 0-1 range.
                    // But audio processor energy can result in low values.
                    // Let's amplify a bit.
                    let amplified = CGFloat(rms) * 1.0
                    
                    let rawHeight = amplified * height
                    let barHeight = min(max(rawHeight, 2.0), height * 0.8)
                    let currentColor = rawHeight < 2.0 ? Color.gray : barColor
                    
                    // Position
                    // Right-aligned: width - (i * totalWidth) - visualWidth
                    // i=0 -> Rightmost
                    let xPosition = width - (CGFloat(i) * totalBarWidth) - visualBarWidth
                    
                    let rect = CGRect(
                        x: xPosition,
                        y: (height - barHeight) / 2,
                        width: visualBarWidth,
                        height: barHeight
                    )
                    
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(currentColor))
                }
            }
        }
        .frame(height: 72)
        .background(Color.secondary.opacity(0.1)) // Subtle background
        .cornerRadius(12)
        .clipped()
    }
}

#Preview {
    LiveWaveformView(
        samples: (0..<500).map { _ in Float.random(in: 0...0.5) },
        totalDuration: 10.0
    )
    .frame(width: 300)
    .padding()
}

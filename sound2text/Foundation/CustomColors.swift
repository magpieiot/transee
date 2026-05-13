import SwiftUI
import AppKit

// 定义这个包装器，让 SwiftUI 能够使用 AppKit 的 NSVisualEffectView
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active // 确保始终处于激活状态
        return visualEffectView
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Color Extension
extension Color {
    // MARK: - Initializers
    
    /// Initializes a color from a hex string (e.g., "#RRGGBB" or "RRGGBB").
    init(hex: String, opacity: Double = 1.0) {
        let hexClouded = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexClouded).scanHexInt64(&rgb)
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    /// Convenience initializer using 0-255 integer values
    public init(red: Int, green: Int, blue: Int, opacity: Double = 1.0) {
        self.init(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: opacity
        )
    }

    // MARK: - Brand Colors
    static let accentTechPrimary = Color(hex: "4A90E2")  // 科技蓝
    static let accentTechSecondary = Color(hex: "E0EAFD")  // 浅清蓝
    static let accentBrandPrimary = Color(hex: "4F46E5") // 靛蓝 600
    static let accentBrandSecondary = Color(hex:"EEF2FF") // 靛蓝 50
    //Color(hex: "3A6EA5") // 浅蓝色
    static let brandButtonBackground = Color(hex: "4A90E2") // Renamed to avoid conflict

    // MARK: - Neutral Colors
    static let lightGrayBackground = Color(hex: "#EBEBEB")
    static let mediumGrayBackground = Color(hex: "#C0C0C0")
    static let mainBackground = Color.white
    static let sidebarBackground = Color(hex: "F8F9FA")
    static let darkGrayText = Color(hex: "#2D3047")
    
    // MARK: - Status Colors
    static let successGreen = Color(hex: "629677")
    static let warningYellow = Color(hex: "FF6700")
    static let crayolaRed = Color(hex: "EF3054")
    static let munsellBlue = Color(hex: "3587A4")
    static let babyBlue = Color(hex: "88ccf1")

    // 文字颜色
    static let textPrimary = Color(hex: "6B7280")  // 未选中状态
    static let textSecondary = Color(hex: "374151") // 悬停状态
    static let textTertiary = Color(hex: "9CA3AF") // 辅助文字
    
    // 按钮背景
    static let buttonBackground = Color(hex: "E5E7EB")
    static let buttonHover = Color(hex: "D1D5DB")
    
    // 状态栏文字
    static let statusText = Color(hex: "6B7280")
    
    // MARK: - Gradients
    static let gradientPink = Color(red: 210, green: 153, blue: 194)
    static let gradientYellow = Color(red: 254, green: 249, blue: 215)

    static let gradientTechButton = LinearGradient(
        gradient: Gradient(colors: [accentTechPrimary, accentBrandPrimary]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension ShapeStyle where Self == LinearGradient {
    static var gradientTechButton: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.accentTechPrimary, Color.accentBrandPrimary]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var sunsetGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.orange, Color.red]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - App Color Constants
/*
struct ColorConstants {
    // 主色调（科技感青蓝）
    static let primary = Color(hex: "4A90E2")
    
    // 辅助色调（浅青蓝，用于按钮边框/悬停状态）
    static let secondary = Color(hex: "E0EAFD")
    
    // 背景色
    static let sidebarBackground = Color(hex: "F8F9FA")
    static let mainBackground = Color.white
    
    // 文字颜色
    static let textPrimary = Color(hex: "6B7280")  // 未选中状态
    static let textSecondary = Color(hex: "374151") // 悬停状态
    static let textTertiary = Color(hex: "9CA3AF") // 辅助文字
    
    // 按钮背景
    static let buttonBackground = Color(hex: "E5E7EB")
    static let buttonHover = Color(hex: "D1D5DB")
    
    // 状态栏文字
    static let statusText = Color(hex: "6B7280")
}
*/

// MARK: - Demo View
struct CustomColorsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Color Library Test")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.bottom, 10)
                
                Group {
                    SectionHeader(title: "Brand Colors")
                    ColorGrid(colors: [
                        ("Tech Primary", Color.accentTechPrimary),
                        ("Tech Secondary", Color.accentTechSecondary),
                        ("Brand Primary", Color.accentBrandPrimary),
                        ("Brand Secondary", Color.accentBrandSecondary),
                        ("Brand Button", Color.brandButtonBackground)
                    ])
                    
                    SectionHeader(title: "Neutral Colors")
                    ColorGrid(colors: [
                        ("Light Gray BG", Color.lightGrayBackground),
                        ("Medium Gray BG", Color.mediumGrayBackground),
                        ("Main BG", Color.mainBackground),
                        ("Sidebar BG", Color.sidebarBackground),
                        ("Dark Gray Text", Color.darkGrayText)
                    ])
                    
                    SectionHeader(title: "Status Colors")
                    ColorGrid(colors: [
                        ("Success Green", Color.successGreen),
                        ("Warning Yellow", Color.warningYellow),
                        ("Crayola Red", Color.crayolaRed),
                        ("Munsell Blue", Color.munsellBlue),
                        ("Baby Blue", Color.babyBlue)
                    ])
                }
                
                Group {
                    SectionHeader(title: "Text & Interface")
                    ColorGrid(colors: [
                        ("Text Primary", Color.textPrimary),
                        ("Text Secondary", Color.textSecondary),
                        ("Text Tertiary", Color.textTertiary),
                        ("Status Text", Color.statusText),
                        ("Button BG", Color.buttonBackground),
                        ("Button Hover", Color.buttonHover)
                    ])
                    
                    SectionHeader(title: "Gradients")
                    HStack(spacing: 20) {
                        GradientBox(title: "Pink", color: Color.gradientPink)
                        GradientBox(title: "Yellow", color: Color.gradientYellow)
                        
                        VStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [Color.accentTechPrimary, Color.accentBrandPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 150, height: 80)
                            Text("Tech Gradient")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color.mainBackground)
        .frame(minWidth: 600, minHeight: 800)
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Divider()
        }
    }
}

private struct ColorGrid: View {
    let colors: [(String, Color)]
    let columns = [GridItem(.adaptive(minimum: 120), spacing: 20)]
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(colors, id: \.0) { item in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.1)
                        .frame(height: 80)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                    
                    Text(item.0)
                        .font(.caption.bold())
                        .lineLimit(1)
                    
                    // Display hex value if possible or just color name
                    Text(item.1.description.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct GradientBox: View {
    let title: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 100, height: 80)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
#Preview {
    CustomColorsView()
}

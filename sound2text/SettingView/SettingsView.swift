//
//  SettingView.swift
//  sound2text
//
//  Created by gavanwang on 8/24/25.
//


import SwiftUI
import Foundation
import AppKit

enum SettingsCategory: String, CaseIterable, Identifiable {
    //case general = "General"
    case appearance = "Appearance"
    case prompt = "Prompt"
    case model = "Model"
    //ase audio = "Audio"
    case export = "Export"
    case about = "About"
    var id: String { self.rawValue }
    var symbolName: String {
        switch self {
            //case .general: return "gearshape"
            case .appearance: return "sun.min.fill"
            case .prompt: return "textformat.characters"
            case .model: return "circle.hexagongrid"
            //case .audio: return "waveform.badge.microphone"
            case .export: return "square.and.arrow.up.on.square"
            case .about: return "info.circle"
        }
    }
    var iconColor: Color {
        switch self {
            //case .general: return .accentBrandPrimary
            case .appearance: return .accentBrandSecondary
            case .prompt: return .accentBrandPrimary
            case .model: return .successGreen
            //case .audio: return .accentBrandPrimary
            case .export: return .gradientYellow
            case .about: return .accentBrandPrimary
        }
    }
    
    var displayName: String {
        switch self {
        case .appearance:
            return NSLocalizedString("Appearance", comment: "Appearance settings category")
        case .prompt:
            return NSLocalizedString("Prompt", comment: "Prompt settings category")
        case .model:
            return NSLocalizedString("Model", comment: "Model settings category")
        case .export:
            return NSLocalizedString("Export", comment: "Export settings category")
        case .about:
            return NSLocalizedString("About", comment: "About settings category")
        }
    }
}


// 主设置视图
struct SettingsView: View {
    @ObservedObject var appModel: AppStateModel
    @State private var selectedCategory: SettingsCategory? = .appearance // 默认选中通用设置
    @EnvironmentObject var whisperService: WhisperService
    @EnvironmentObject var appStateManager: AppStateManager
    
    var body: some View {
        HStack(spacing: 0) {
            settingsSideBar()
                .id("settings-sidebar-\(appStateManager.viewID.uuidString)")
            Divider()
            settingsDetailView()
                .id("settings-detail-\(appStateManager.viewID.uuidString)")
        }
        .preferredColorScheme(appStateManager.preferredColorScheme)
        .environment(\.locale, appStateManager.locale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 900, minHeight: 640)
        .background(WindowAccessor { window in
            if let delegate = window.delegate as? MyWindowDelegate, delegate.windowTitle == "Settings" { return }
            let delegate = MyWindowDelegate(windowTitle: "Settings", appModel: appModel)
            delegate.onRequestClose = { self.closeModal() }
            window.delegate = delegate
            windowDelegates["Settings"] = delegate
        })
    }

    // 关闭模态窗口并更新 AppStateModel
    private func closeModal(){
        NSApp.stopModal()
        NSApplication.shared.keyWindow?.close()
    }

    private func settingsSideBar() -> some View {
        VStack(spacing: 8) {
            ForEach(SettingsCategory.allCases) { category in
                sideButton(selectedCategory: $selectedCategory, category: category)
            }
            Spacer()
        }
        .padding()
        .background(Color.lightGrayBackground.opacity(0.1)) // 确保有背景色
        .cornerRadius(16)
        //.shadow(color: .gray.opacity(0.2), radius: 8, x: 4, y: 4)
        .frame(width: 200)
        .padding()
    }

    private func settingsDetailView() -> some View {
        ScrollViewReader { proxy in
            Form {
                //VStack(alignment: .leading) {
                    /*
                    SettingsGeneralView()
                        .id(SettingsCategory.general)
                    */
                    SettingsAppearanceView()
                        .id(SettingsCategory.appearance)
                    SettingsPromptView()
                        .id(SettingsCategory.prompt)
                    SettingsModelView()
                        .id(SettingsCategory.model)
                    /*
                    SettingsAudioView()
                        .id(SettingsCategory.audio)
                    */
                    SettingsExportView()
                        .id(SettingsCategory.export)
                    SettingsAboutView()
                        .id(SettingsCategory.about)
                //}
            }
            .formStyle(.grouped) // 将 Form 呈现为分组样式，在 macOS 上有卡片效果
            //.frame(maxWidth: .infinity) 
            .onChange(of: selectedCategory) { _, newValue in
                if let category = newValue {
                    withAnimation {
                        proxy.scrollTo(category, anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/*
// 侧边栏视图
struct SettingsSidebar: View {
    @Binding var selectedCategory: SettingsCategory?
    
    var body: some View {
        VStack {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                sideButton(selectedCategory: $selectedCategory, category: category)
            }
            .listStyle(.sidebar) // macOS 风格的侧边栏列表
            .cornerRadius(16)
            .shadow(color: .gray.opacity(0.2), radius: 8, x: 4, y: 4)
            .frame(width: 200)
        }
        .padding()
    }
}


// 详细设置视图
struct SettingsDetailView: View {
    // @ObservedObject var whisperService: WhisperService
    let selectedCategory: SettingsCategory?

    var body: some View {
        
        ScrollView {
            VStack(alignment: .leading) {
                Form{
                SettingsGeneralView()
                .id(SettingsCategory.general.id)
                SettingsModelView()
                .id(SettingsCategory.model.id)
                SettingsExportView()
                .id(SettingsCategory.output.id)
                Spacer()
                }
                .formStyle(.grouped) // 将 Form 呈现为分组样式，在 macOS 上有卡片效果
                .padding()
            }
            .frame(height: 1000)
        }
        // 对于 NavigationSplitView 的 Detail 部分，默认的标题显示在内容区域
        // 但为了统一，我们通过 .navigationTitle 在每个子视图中设置
    }
}
*/

struct sideButton: View{
    @Binding var selectedCategory: SettingsCategory?
    let category: SettingsCategory
    
    @State private var isHoveringButton = false
    
    var body: some View{

        SideBarButton(
            title: category.displayName, 
            icon: category.symbolName,
            minWidth: 80,
            maxWidth: 140,
            isActive: category == selectedCategory
        ) {
            selectedCategory = category
        }
    }
}

#if os(macOS)
// 窗口访问器，用于获取当前视图所在的窗口
// 当视图出现在窗口中时，调用 onWindow 闭包并传递窗口实例
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}
#endif


#Preview {
    SettingsView(appModel: AppStateModel() )
        .environmentObject(WhisperService())
        .environmentObject(AppStateManager())
}



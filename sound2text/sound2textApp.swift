//
//  sound2textApp.swift
//  sound2text
//
//  Created by gavanwang on 8/19/25.
//

import SwiftUI
import AppKit
import Foundation
import Combine

// 全局持有 WindowDelegates，否则它们会被 ARC 释放
@MainActor var windowDelegates: [String: MyWindowDelegate] = [:]

@main
struct tarnseeApp: App {
    @StateObject var appModel = AppStateModel()
    @StateObject var whisperService: TranscriptionService = TranscriptionService()
    @StateObject var permissionManager: PermissionManager = PermissionManager.shared
    @StateObject var appStateManager: AppStateManager = AppStateManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appModel)
                .environmentObject(whisperService)
                .environmentObject(permissionManager)
                .environmentObject(appStateManager)
                .preferredColorScheme(appStateManager.preferredColorScheme)
                .environment(\.locale, appStateManager.locale)
                .id(appStateManager.viewID)
                .onAppear {
                    appDelegate.setup(with: appModel, whisperService: whisperService, appStateManager: appStateManager)
                    Task { @MainActor in
                        appDelegate.enterMainWindowFullScreenIfNeeded(appModel: appModel)
                    }
                    // 初始化模型
                    whisperService.modelManager.fetchModels()
                }
        }
        .commands {
            // 确保Command+Q 也是通过 AppDelegate.applicationShouldTerminate 处理
            CommandGroup(replacing: .appTermination) {
                Button("退出 \(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App")") {
                     NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                // 留空表示移除该组的所有默认项 (New, Open, Open Recent)
                // 如果你想保留部分，可以这里重新添加特定的 MenuItem
            }
            /*
            CommandGroup(replacing: .textEditing) {
                // 移除 Edit 菜单组所有默认项
            }
            CommandGroup(replacing: .textFormatting) {
                // 移除 View 菜单组所有默认项
            }
            */
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        
#if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(action: {
                    NSApp.sendAction(#selector(AppDelegate.showSettingsModal), to: nil, from: nil)
                }) {
                    Label("Settings…", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
    }
}
#endif
    }

}

// 应用状态模型
class AppStateModel: ObservableObject {
    @Published var hasUnsavedChanges: Bool = false {
        didSet {
            print("App State: Has unsaved changes: \(hasUnsavedChanges)")
        }
    }

    @Published var isShowSettingsSheet: Bool = false
    
    func simulateWork() {
        hasUnsavedChanges = true
    }
    
    func saveChanges() {
        hasUnsavedChanges = false
        print("Changes saved!")
    }
}

// Command+Q 中使用的 AppDelegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var didRequestMainFullScreen = false
    private var mainWindowBecomeMainObserver: Any?

    func enterMainWindowFullScreenIfNeeded(appModel: AppStateModel) {
        guard !didRequestMainFullScreen else { return }
        didRequestMainFullScreen = true

        if let window = NSApp.mainWindow ?? NSApp.keyWindow, !shouldIgnoreForFullScreen(window: window) {
            enterFullScreenIfPossible(window: window, appModel: appModel)
            return
        }
        
        if mainWindowBecomeMainObserver == nil {
            mainWindowBecomeMainObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard let window = notification.object as? NSWindow else { return }
                guard !self.shouldIgnoreForFullScreen(window: window) else { return }

                Task { @MainActor in
                    self.enterFullScreenIfPossible(window: window, appModel: appModel)
                }   
                //self.enterFullScreenIfPossible(window: window, appModel: appModel)

                if let observer = self.mainWindowBecomeMainObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.mainWindowBecomeMainObserver = nil
                }
            }
        }
        
    }

    private func shouldIgnoreForFullScreen(window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.isModalPanel { return true }
        return false
    }

    private func enterFullScreenIfPossible(window: NSWindow, appModel: AppStateModel) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        if windowDelegates["Main Window"] == nil {
            let delegate = MyWindowDelegate(windowTitle: "Main Window", appModel: appModel)
            window.delegate = delegate
            windowDelegates["Main Window"] = delegate
            print("Main Window delegate set.")
        }
        
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrame(visible, display: true)
        } else {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            window.setFrame(visible, display: true)
        }
    }

    private func toggleFullScreenWhenPossible(window: NSWindow, attempt: Int = 0) {
        guard attempt < 30 else { return }
        if shouldIgnoreForFullScreen(window: window) { return }
        if !window.isVisible { return }
        if window.styleMask.contains(.fullScreen) { return }
        if NSApp.modalWindow != nil || window.attachedSheet != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.toggleFullScreenWhenPossible(window: window, attempt: attempt + 1)
            }
            return
        }
        window.toggleFullScreen(nil)
    }
    // 使用一个 `@Published` 属性来观察 appModel，或者直接通过一个弱引用来避免循环引用
    // 如果 AppStateModel 在整个 App 生命周期中都存在，强引用也无妨
    var appStateModel: AppStateModel! // 在 setup() 中注入
    var whisperService: TranscriptionService! // 新增属性，用于存储 TranscriptionService 实例
    var appStateManager: AppStateManager!
    var settingsWindow: NSWindow? // 用于保持设置窗口的单例引用
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    override init() {
        super.init()
        print("AppDelegate default init called.")
    }
    // 这是一个可以在外部调用的方法，用于设置 appStateModel
    func setup(with appModel: AppStateModel, whisperService: TranscriptionService, appStateManager: AppStateManager) {
        self.appStateModel = appModel
        self.whisperService = whisperService // 存储 TranscriptionService 实例
        self.appStateManager = appStateManager
        print("AppDelegate setup with AppStateModel complete.")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // 关闭最后一个窗口时终止应用程序
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("APP: Application is trying to terminate...")
        // Only for test
        //hasCompletedOnboarding = false
        // 
        guard let appModel = appStateModel else {
            print("Error: appStateModel not set in AppDelegate. Allowing termination.")
            return .terminateNow
        }
        if appModel.hasUnsavedChanges {
            let alert = NSAlert()
            // ... (同上文的 alert 代码)
            alert.messageText = "有未保存的更改"
            alert.informativeText = "您有未保存的工作。是否要退出并放弃更改？"
            alert.addButton(withTitle: "退出并放弃")
            alert.addButton(withTitle: "取消")
            
            NSApplication.shared.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                return .terminateNow
            } else {
                return .terminateCancel
            }
        } else {
            return .terminateNow
        }
    }

    @objc func showSettingsModal() {
        // 如果窗口已经存在，直接关闭它。我们每次都创建一个全新窗口，
        // 以保证 SwiftUI 和 AppKit 层的外观上下文 (Appearance) 被完美且干净地初始化。
        if let window = settingsWindow {
            window.close()
            settingsWindow = nil
        }

        let hosting = NSHostingController(
            rootView: SettingsView(
                appModel: appStateModel
            )
            .environmentObject(whisperService)
            .environmentObject(appStateManager)
            .preferredColorScheme(appStateManager.preferredColorScheme)
            .environment(\.locale, appStateManager.locale)
            .id(appStateManager.viewID)
        )
        
        // 自适应屏幕尺寸：宽度为屏幕宽度的 60%，高度为屏幕高度的 70%
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        print("@@@DEBUG: Screen Visible Frame: \(screenFrame)")

        let desiredWidth = min(screenFrame.width * 0.6, 900)
        let desiredHeight = min(screenFrame.height - 128, 600)
        print("@@@DEBUG: Desired Window Size: \(desiredWidth) x \(desiredHeight)")

        let desiredRect = NSRect(
            x: screenFrame.midX - desiredWidth / 2,
            y: screenFrame.midY - desiredHeight / 2,
            width: desiredWidth,
            height: desiredHeight
        )
        print("@@@DEBUG: Desired Content Rect: \(desiredRect)")

        let window = NSWindow(
            contentRect: desiredRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setting"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        applyAppearance(to: window)

        let desiredFrame = window.frameRect(forContentRect: desiredRect)
        window.setFrame(desiredFrame, display: true)

        self.settingsWindow = window // 保存引用

        NSApp.activate(ignoringOtherApps: true) // 激活应用程序，确保窗口出现在前端
        window.makeKeyAndOrderFront(nil) // 非模态显示
    }

    private func applyAppearance(to window: NSWindow) {
        switch appStateManager.appTheme {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

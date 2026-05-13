//
//  MyWindowDelegate.swift
//  sound2text
//
//  Created by gavanwang on 10/20/25.
//


import SwiftUI
import AppKit

class MyWindowDelegate: NSObject, NSWindowDelegate {
    var windowTitle: String // 用于识别是哪个窗口的代理
    var appModel: AppStateModel // 假设你有一个共享状态来判断是否有未保存的工作
    var onRequestClose: (() -> Void)?

    init(windowTitle: String, appModel: AppStateModel) {
        self.windowTitle = windowTitle
        self.appModel = appModel
        super.init()
        print("[\(windowTitle)] WindowDelegate initialized.")
    }
    
    // 应用程序窗口的标题
    func windowTitleForRepresentedObject(_ sender: NSWindow) -> String? {
        return windowTitle // 可以用来设置窗口标题，但通常由 SwiftUI 的.navigationTitle或.windowTitleForContent()设置
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("[\(windowTitle)] Window is trying to close (red button clicked)...")
        onRequestClose?()

        if appModel.hasUnsavedChanges {
            // 如果有未保存的更改，显示确认对话框
            let alert = NSAlert()
            alert.messageText = "有未保存的更改"
            alert.informativeText = "您有未保存的工作。是否要关闭窗口并放弃更改？"
            alert.addButton(withTitle: "关闭并放弃")
            alert.addButton(withTitle: "取消")
            
            // 确保在主线程上显示警报
            NSApplication.shared.activate(ignoringOtherApps: true) // 确保应用前置
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn { // 用户点击 "关闭并放弃"
                print("[\(windowTitle)] User chose to close anyway.")
                appModel.hasUnsavedChanges = false // 假设关闭即放弃
                return true // 允许关闭窗口
            } else { // 用户点击 "取消"
                print("[\(windowTitle)] User cancelled closing.")
                return false // 阻止关闭窗口
            }
        } else {
            // 没有未保存的更改，允许关闭窗口
            print("[\(windowTitle)] No unsaved changes, closing now.")
            return true
        }
    }
    
    // 其他可选的 NSWindowDelegate 方法
    func windowWillClose(_ notification: Notification) {
        print("[\(windowTitle)] Window will close.")
    }
}

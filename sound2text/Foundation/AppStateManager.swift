//
//  AppStateManager.swift
//  sound2text
//
//  Created by gavanwang on 2026/3/15.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// 应用状态管理器
@MainActor
class AppStateManager: ObservableObject {
    // MARK: - Published Properties
    @Published var appLanguage: AppLanguage = .english {
        didSet {
            guard !isLoadingSavedSettings else { return }
            Task { await updateLanguage() }
        }
    }
    
    @Published var appTheme: AppTheme = .system {
        didSet {
            guard !isLoadingSavedSettings else { return }
            Task { await updateTheme() }
        }
    }
    
    @Published var preferredColorScheme: ColorScheme? = nil
    @Published var viewID = UUID()
    @Published var languageDidChange = false
    @Published var locale: Locale = .autoupdatingCurrent
    private var currentLanguageCode: String = "en"
    private var isLoadingSavedSettings = false
    
    // MARK: - Initialization
    init() {
        loadSavedSettings()
    }
    
    // MARK: - Private Methods
    private func loadSavedSettings() {
        isLoadingSavedSettings = true
        defer { isLoadingSavedSettings = false }

        if let savedThemeRaw = UserDefaults.standard.string(forKey: "appTheme"),
           let savedTheme = AppTheme(rawValue: savedThemeRaw) {
            appTheme = savedTheme
        }

        if let savedLanguageRaw = UserDefaults.standard.string(forKey: "appLanguage"),
           let savedLanguage = AppLanguage(rawValue: savedLanguageRaw) {
            appLanguage = savedLanguage
        }

        switch appTheme {
        case .system:
            preferredColorScheme = nil
        case .light:
            preferredColorScheme = .light
        case .dark:
            preferredColorScheme = .dark
        }
#if os(macOS)
        switch appTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
#endif

        switch appLanguage {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            Bundle.setAppLanguage(nil)
            locale = .autoupdatingCurrent
            currentLanguageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"

        default:
            let languageCode = getLanguageCode(for: appLanguage)
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            Bundle.setAppLanguage(languageCode)
            locale = Locale(identifier: languageCode)
            currentLanguageCode = languageCode
        }

        viewID = UUID()
    }
    
    private func updateTheme() async {
        print("@@@DEBUG updateTheme called, appTheme=\(appTheme.rawValue)")
        // 更新应用主题
        switch appTheme {
        case .system:
            preferredColorScheme = nil
        case .light:
            preferredColorScheme = .light
        case .dark:
            preferredColorScheme = .dark
        }
#if os(macOS)
        switch appTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
#endif
        
        print("@@@DEBUG updateTheme: preferredColorScheme now = \(String(describing: preferredColorScheme))")
        
        // 保存设置到 UserDefaults
        UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme")
        
        // 刷新视图
        await refreshView()
    }
    
    private func updateLanguage() async {
        UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")

        switch appLanguage {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            Bundle.setAppLanguage(nil)
            locale = .autoupdatingCurrent
            currentLanguageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"

        default:
            let languageCode = getLanguageCode(for: appLanguage)
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            Bundle.setAppLanguage(languageCode)
            locale = Locale(identifier: languageCode)
            currentLanguageCode = languageCode
        }

        languageDidChange = true
        await refreshView()
    }
    
    private func refreshView() async {
        // 通过改变 viewID 来触发视图刷新
        self.viewID = UUID()
        
        // 延迟后再次刷新，确保所有视图都收到更新
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
        self.viewID = UUID()
    }
    
    private func getLanguageCode(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return Locale.current.language.languageCode?.identifier ?? "en"
        case .english:
            return "en"
        case .chineseSimplified:
            return "zh-Hans"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .spanish:
            return "es"
        case .german:
            return "de"
        case .french:
            return "fr"
        }
    }
    
    // MARK: - Public Methods
    func resetToSystemTheme() {
        Task { appTheme = .system }
    }
    
    func resetToEnglishLanguage() {
        Task { appLanguage = .english }
    }
    
    func setTheme(_ theme: AppTheme) {
        Task { appTheme = theme }
    }
    
    func setLanguage(_ language: AppLanguage) {
        Task { appLanguage = language }
    }
    
    func forceLanguageRefresh() {
        // 强制刷新语言设置
        languageDidChange = false
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒延迟
            self.languageDidChange = true
        }
    }
}

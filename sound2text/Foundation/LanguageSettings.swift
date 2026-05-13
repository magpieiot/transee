//
//  AppLanguage.swift
//  sound2text
//
//  Created by gavanwang on 2026/3/14.
//

import Foundation
import SwiftUI
import ObjectiveC

// 语言设置枚举
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .system:
            return "Follow OS"
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .spanish:
            return "Español"
        case .german:
            return "Deutsch"
        case .french:
            return "Français"
        }
    }
}

// 应用主题枚举
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { self.rawValue }
    
    var appThemeDescription: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "System theme")
        case .light:
            return NSLocalizedString("Light", comment: "Light theme")
        case .dark:
            return NSLocalizedString("Dark", comment: "Dark theme")
        }
    }
}

private enum AppLanguageAssociatedKeys {
    nonisolated(unsafe) static var bundle: UInt8 = 0
}

private final class AppLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &AppLanguageAssociatedKeys.bundle) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    static func setAppLanguage(_ languageCode: String?) {
        object_setClass(Bundle.main, AppLanguageBundle.self)

        guard let languageCode,
              let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            objc_setAssociatedObject(Bundle.main, &AppLanguageAssociatedKeys.bundle, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }

        objc_setAssociatedObject(Bundle.main, &AppLanguageAssociatedKeys.bundle, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
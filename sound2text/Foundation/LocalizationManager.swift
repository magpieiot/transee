//
//  LocalizationManager.swift
//  sound2text
//
//  Created by gavanwang on 2026/3/14.
//

import Foundation
import SwiftUI

@MainActor
class LocalizationManager: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationManager()
    
    @AppStorage("appLanguage") var language: String = "en" {
        didSet {
            updateLanguage()
        }
    }
    
    private init() {}
    
    func updateLanguage() {
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }
    
    func localizedString(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, comment: comment)
    }
}

extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
}
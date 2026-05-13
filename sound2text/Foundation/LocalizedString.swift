//
//  LocalizedString.swift
//  sound2text
//
//  Created by gavanwang on 2026/3/14.
//

import Foundation
import SwiftUI

// 全局本地化函数
func LocalizedString(_ key: String, comment: String = "") -> String {
    return NSLocalizedString(key, comment: comment)
}
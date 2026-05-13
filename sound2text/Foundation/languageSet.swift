//
//  languarage.swift
//  sound2text
//
//  Created by gavanwang on 2026/2/4.
//

import SwiftUI
import Foundation

public struct LanguageWhisperResources {
    public static func getLocalizedName(for language: String) -> String {
        return names[language.lowercased()] ?? language
    }

    public static func getLanguageName(for language: String) -> String {
        return name2name[language] ?? language
    }

    public static func getDisplayString(for language: String) -> String {
        return "\(language) (\(getLocalizedName(for: language)))"
    }

    public static func getDisplayStringList() -> [String] {
        return orderedKeys.compactMap { names[$0] }
    }

    private static let orderedKeys: [String] = [
        "english", "chinese", "german", "spanish", "russian", "korean", "french", "japanese", "portuguese", "turkish",
        "polish", "catalan", "dutch", "arabic", "swedish", "italian", "indonesian", "hindi", "finnish", "vietnamese",
        "hebrew", "ukrainian", "greek", "malay", "czech", "romanian", "danish", "hungarian", "tamil", "norwegian",
        "thai", "urdu", "croatian", "bulgarian", "lithuanian", "latin", "maori", "malayalam", "welsh", "slovak",
        "telugu", "persian", "latvian", "bengali", "serbian", "azerbaijani", "slovenian", "kannada", "estonian", "macedonian",
        "breton", "basque", "icelandic", "armenian", "nepali", "mongolian", "bosnian", "kazakh", "albanian", "swahili",
        "galician", "marathi", "punjabi", "sinhala", "khmer", "shona", "yoruba", "somali", "afrikaans", "occitan",
        "georgian", "belarusian", "tajik", "sindhi", "gujarati", "amharic", "yiddish", "lao", "uzbek", "faroese",
        "haitian creole", "pashto", "turkmen", "nynorsk", "maltese", "sanskrit", "luxembourgish", "myanmar", "tibetan", "tagalog",
        "malagasy", "assamese", "tatar", "hawaiian", "lingala", "hausa", "bashkir", "javanese", "sundanese", "cantonese"
    ]

    private static let code2name: [String: String] = [
        "en": "english",
        "zh": "chinese",
        "de": "german",
        "es": "spanish",
        "ru": "russian",
        "ko": "korean",
        "fr": "french",
        "ja": "japanese",
        "pt": "portuguese",
        "tr": "turkish",
        "pl": "polish",
        "ca": "catalan",
        "nl": "dutch",
        "ar": "arabic",
        "sv": "swedish",
        "it": "italian",
        "id": "indonesian",
        "hi": "hindi",
        "fi": "finnish",
        "vi": "vietnamese",
        "he": "hebrew",
        "uk": "ukrainian",
        "el": "greek",
        "ms": "malay",
        "cs": "czech",
        "ro": "romanian",
        "da": "danish",
        "hu": "hungarian",
        "ta": "tamil",
        "no": "norwegian",
        "th": "thai",
        "ur": "urdu",
        "hr": "croatian",
        "bg": "bulgarian",
        "lt": "lithuanian",
        "la": "latin",
        "mi": "maori",
        "ml": "malayalam",
        "cy": "welsh",
        "sk": "slovak",
        "te": "telugu",
        "fa": "persian",
        "lv": "latvian",
        "bn": "bengali",
        "sr": "serbian",
        "az": "azerbaijani",
        "sl": "slovenian",
        "kn": "kannada",
        "et": "estonian",
        "mk": "macedonian",
        "br": "breton",
        "eu": "basque",
        "is": "icelandic",
        "hy": "armenian",
        "ne": "nepali",
        "mn": "mongolian",
        "bs": "bosnian",
        "kk": "kazakh",
        "sq": "albanian",
        "sw": "swahili",
        "gl": "galician",
        "mr": "marathi",
        "pa": "punjabi",
        "si": "sinhala",
        "km": "khmer",
        "sn": "shona",
        "yo": "yoruba",
        "so": "somali",
        "af": "afrikaans",
        "oc": "occitan",
        "ka": "georgian",
        "be": "belarusian",
        "tg": "tajik",
        "sd": "sindhi",
        "gu": "gujarati",
        "am": "amharic",
        "yi": "yiddish",
        "lo": "lao",
        "uz": "uzbek",
        "fo": "faroese",
        "ht": "haitian creole",
        "ps": "pashto",
        "tk": "turkmen",
        "nn": "nynorsk",
        "mt": "maltese",
        "sa": "sanskrit",
        "lb": "luxembourgish",
        "my": "myanmar",
        "bo": "tibetan",
        "tl": "tagalog",
        "mg": "malagasy",
        "as": "assamese",
        "tt": "tatar",
        "haw": "hawaiian",
        "ln": "lingala",
        "ha": "hausa",
        "ba": "bashkir",
        "jw": "javanese",
        "su": "sundanese",
        "yue": "cantonese",
    ]

    private static let names: [String: String] = [
        "english": "English",
        "chinese": "中文",
        "german": "Deutsch",
        "spanish": "español",
        "russian": "русский",
        "korean": "한국어",
        "french": "français",
        "japanese": "日本語",
        "portuguese": "português",
        "turkish": "Türkçe",
        "polish": "polski",
        "catalan": "català",
        "dutch": "Nederlands",
        "arabic": "العربية",
        "swedish": "svenska",
        "italian": "italiano",
        "indonesian": "Bahasa Indonesia",
        "hindi": "हिन्दी",
        "finnish": "suomi",
        "vietnamese": "Tiếng Việt",
        "hebrew": "עברית",
        "ukrainian": "українська",
        "greek": "Ελληνικά",
        "malay": "Bahasa Melayu",
        "czech": "čeština",
        "romanian": "română",
        "danish": "dansk",
        "hungarian": "magyar",
        "tamil": "தமிழ்",
        "norwegian": "norsk",
        "thai": "ไทย",
        "urdu": "اردو",
        "croatian": "hrvatski",
        "bulgarian": "български",
        "lithuanian": "lietuvių",
        "latin": "Latina",
        "maori": "Māori",
        "malayalam": "മലയാളം",
        "welsh": "Cymraeg",
        "slovak": "slovenčina",
        "telugu": "తెలుగు",
        "persian": "فارسی",
        "latvian": "latviešu",
        "bengali": "বাংলা",
        "serbian": "српски",
        "azerbaijani": "azərbaycan dili",
        "slovenian": "slovenščina",
        "kannada": "ಕನ್ನಡ",
        "estonian": "eesti",
        "macedonian": "македонски",
        "breton": "brezhoneg",
        "basque": "euskara",
        "icelandic": "íslenska",
        "armenian": "հայերեն",
        "nepali": "नेपाली",
        "mongolian": "монгол",
        "bosnian": "bosanski",
        "kazakh": "қазақша",
        "albanian": "shqip",
        "swahili": "Kiswahili",
        "galician": "galego",
        "marathi": "मराठी",
        "punjabi": "ਪੰਜਾਬੀ",
        "sinhala": "සිංහල",
        "khmer": "ភាសាខ្មែរ",
        "shona": "chiShona",
        "yoruba": "Yorùbá",
        "somali": "Soomaali",
        "afrikaans": "Afrikaans",
        "occitan": "occitan",
        "georgian": "ქართული",
        "belarusian": "беларуская",
        "tajik": "тоҷиκӣ",
        "sindhi": "سنڌي",
        "gujarati": "ગુજરાતી",
        "amharic": "አማርኛ",
        "yiddish": "ייִדיש",
        "lao": "ພາສາລາວ",
        "uzbek": "oʻzbekcha",
        "faroese": "føroyskt",
        "haitian creole": "Kreyòl ayisyen",
        "pashto": "پښتو",
        "turkmen": "türkmençe",
        "nynorsk": "nynorsk",
        "maltese": "Malti",
        "sanskrit": "संस्कृतम्",
        "luxembourgish": "Lëtzebuergesch",
        "myanmar": "မြန်မာစာ",
        "tibetan": "བོད་སྐད་",
        "tagalog": "Tagalog",
        "malagasy": "Malagasy",
        "assamese": "অসমীয়া",
        "tatar": "татарча",
        "hawaiian": "ʻŌlelo Hawaiʻi",
        "lingala": "Lingála",
        "hausa": "Hausa",
        "bashkir": "башҡортса",
        "javanese": "Basa Jawa",
        "sundanese": "Basa Sunda",
        "cantonese": "粵語"
    ]

    // 创建一个新的字典，将value 映射到 key
    private static let name2name: [String: String] = Dictionary(uniqueKeysWithValues: names.map { ($0.value, $0.key) })
}


import Foundation

class LanguageUtils {
    
    /// 根据 languageCode 获取语言名称（基于当前系统语言）
    static func getLanguageName(code: String) -> String? {
        return Locale.current.localizedString(forIdentifier: code)
    }
    
    /// 根据 languageCode 获取语言本名（该语言自己的名称）
    static func getLanguageLocalizedName(code: String) -> String? {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)
    }
    
    /// 根据 languageCode 获取语言名称（指定显示语言）
    static func getLanguageName(code: String, in localeIdentifier: String) -> String? {
        let locale = Locale(identifier: localeIdentifier)
        return locale.localizedString(forIdentifier: code)
    }
    
    /// 提取纯语言代码（如 "zh-CN" -> "zh"）
    static func extractLanguageCode(from code: String) -> String {
        return code.components(separatedBy: "-")[0]
    }
    
    /// 获取所有支持的语言列表
    static func getAllSupportedLanguages() -> [(code: String, name: String, localizedName: String)] {
        var languages: [(code: String, name: String, localizedName: String)] = []
        
        for code in Locale.LanguageCode.isoLanguageCodes {
            if let name = Locale.current.localizedString(forIdentifier: code.identifier),
               let localizedName = Locale.current.localizedString(forIdentifier: code.identifier) {
                languages.append((code.identifier, name, localizedName))
            }
        }
        
        // 按本地化名称排序
        return languages.sorted { $0.localizedName < $1.localizedName }
    }
}
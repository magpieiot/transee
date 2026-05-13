//
//  GeneralSettingsView.swift
//  sound2text
//
//  Created by gavanwang on 8/24/25.
//

import CoreML
import Foundation
// GeneralSettingsView.swift
import SwiftUI
import ServiceManagement
import OSLog
import AlertToast


struct SettingsGeneralView: View {
    @StateObject private var launchManager = LaunchAtLoginManager()
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var body: some View {
        Section {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0 }
            ))
            .toggleStyle(.switch)  // MacOS风格的开关
        } header: {
            Text(NSLocalizedString("General", comment: "General settings section header"))
        }
        .onAppear {
            launchAtLogin = launchManager.isEnabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            launchManager.setEnabled(newValue)
        }
    }
}

struct SettingsAppearanceView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @AppStorage("fontSize") private var fontSize: Double = 1.0  // 默认值
    @AppStorage("resultTextFontSize") private var resultTextFontSize: Double = 14.0  // 默认

    var body: some View {
        Section {
            Picker(NSLocalizedString("App Language", comment: "App language picker label"), selection: $appStateManager.appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)  // 默认的下拉菜单风格

            Picker(NSLocalizedString("App Theme", comment: "App theme picker label"), selection: $appStateManager.appTheme) {
                Text(AppTheme.system.appThemeDescription).tag(AppTheme.system)
                Text(AppTheme.light.appThemeDescription).tag(AppTheme.light)
                Text(AppTheme.dark.appThemeDescription).tag(AppTheme.dark)
            }
            .pickerStyle(.segmented)  // 分段选择器

            /*
            Picker(NSLocalizedString("Font Size", comment: "Font size picker label"), selection: $resultTextFontSize) {
                Text(NSLocalizedString("Small", comment: "Small font size")).tag(12.0)
                Text(NSLocalizedString("Medium", comment: "Medium font size")).tag(14.0)
                Text(NSLocalizedString("Large", comment: "Large font size")).tag(16.0)
            }
            .pickerStyle(.segmented)  // 分段选择器
            */
        } header: {
            Text(NSLocalizedString("Appearance", comment: "Appearance settings section header"))
        }
    }
}

struct SettingsPromptView: View {
    @EnvironmentObject var whisperService: WhisperService
    @State private var isPromptExpanded: Bool = false
    @State private var isShowAddPromptDialog: Bool = false
    @State private var isShowEditPromptDialog: Bool = false
    @State private var isShowDeleteAlert: Bool = false
    @State private var indexForEditPrompt: Int = 0
    @State private var promptText: String = ""
    @State private var languageName: String = "English"
    @State private var languageCode: String = ""

    private var availableLanguages: [String] {
        let existingCodes = Set(whisperService.settings.initialPrompts.compactMap { $0.languageCode })
        return LanguageWhisperResources.getDisplayStringList().filter { language in
            let code = LanguageWhisperResources.getLanguageName(for: language)
            return !existingCodes.contains(code)
        }
    }

    var body: some View {
        Section {
            //
            VStack(alignment: .leading) {
                Toggle(NSLocalizedString("Prompt Prefill", comment: "Prompt prefill toggle label"), isOn: $whisperService.settings.enablePromptPrefill)
                    .toggleStyle(.switch)  // MacOS风格的开关
                Text(NSLocalizedString("If enabled, the initial prompt will be used as a prompt to generate the first chunk of text.", comment: "Prompt prefill description"))
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading) {
                ExpandableSection(
                    isExpanded: $isPromptExpanded,
                    title: NSLocalizedString("Initial Prompt", comment: "Initial prompt section title"),
                    subtitle: NSLocalizedString("The initial prompt will be used as a prompt to generate the first chunk of text.", comment: "Initial prompt section description"),  
                    showArrow: true,
                    arrowPosition: .right,
                    content: {
                        VStack(alignment: .leading) {
                            ForEach(whisperService.settings.initialPrompts.indices, id: \.self) { index in
                                preDefinePromptBar(index: index)
                            }
                            // New Prompt
                            HStack {
                                Picker("Language", selection: $languageName) {
                                    ForEach(availableLanguages, id: \.self) { language in
                                        Text(language).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)  // 默认的下拉菜单风格
                                .onChange(of: languageName) { oldValue, newValue in
                                    languageCode = LanguageWhisperResources.getLanguageName(for: newValue)
                                    print("@@@DEBUG: languageCode: \(languageCode), languageName: \(languageName)")
                                    
                                }
                                
                                Spacer()    
                                TextField("Prompt", text: $promptText) 
                                    .labelsHidden()
                                    //.fixedSize(horizontal: true, vertical: false)
                                    //.frame(maxWidth: 400)
                                    //.background(Color.secondary.opacity(0.1))
                                    .textFieldStyle(.roundedBorder)  // 圆角边框样式
                                
                                Button(action: {
                                    // 添加新的初始提示
                                    // Add new prompt
                                    print("@@@DEBUG: prompt: \(promptText), languageCode: \(languageCode), languageName: \(languageName)")
                                    whisperService.settings.initialPrompts.append(
                                        PreDefinedPrompt(
                                            prompt: promptText,
                                            languageCode: languageCode,
                                        )
                                    )
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.successGreen)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 16)
                        }
                    }
                )
            }
            .alert("Delete Prompt", isPresented: $isShowDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    whisperService.settings.initialPrompts.remove(at: indexForEditPrompt)
                    isShowDeleteAlert = false
                }
            } message: {
                Text("Are you sure you want to delete this initial prompt?")
            }
        } header: {
            Text(NSLocalizedString("Prompt", comment: "Prompt settings section header"))
        }
    }

    // 预定义提示条
    func preDefinePromptBar(index: Int) -> some View {
        // Ensure index is valid to prevent crash
        guard index >= 0 && index < whisperService.settings.initialPrompts.count else {
            return AnyView(EmptyView())
        }
        
        return AnyView(HStack {
            TextField(
                LanguageWhisperResources.getLocalizedName(for: whisperService.settings.initialPrompts[index].languageCode ?? ""), 
                text: Binding(
                    get: { 
                        if index < whisperService.settings.initialPrompts.count {
                            return whisperService.settings.initialPrompts[index].prompt ?? ""
                        }
                        return ""
                    },
                    set: { 
                        if index < whisperService.settings.initialPrompts.count {
                            whisperService.settings.initialPrompts[index].prompt = $0 
                        }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .padding(4)
            
            Button(action: {
                // 删除内容
                // 弹出确认删除的警告
                indexForEditPrompt = index
                isShowDeleteAlert = true
                
            }) {
                Image(systemName: "trash")
                    .foregroundColor(Color.crayolaRed)
            }
            .buttonStyle(.plain)
            
        })
    }
}

struct SettingsModelView: View {
    @EnvironmentObject var whisperService: WhisperService

    @State private var isEditingRepoName: Bool = false
    @State private var isPromptExpanded: Bool = false
    @State private var isShowAddPromptDialog: Bool = false
    @State private var isShowEditPromptDialog: Bool = false
    @State private var isShowDeleteAlert: Bool = false
    @State private var isShowAlertToast: Bool = false
    @State private var indexForEditPrompt: Int = 0
    @State private var promptText: String = "                                      "
    @State private var languageCode: String = "English"
    @State private var toastMessage: String = ""

    var body: some View {   
        Section {
            HStack {
                Text(NSLocalizedString("Model Repo name", comment: "Model repository name label"))
                Button(action: {
                    toastMessage = NSLocalizedString("Important setting, please modify with caution. Incorrect strings will cause failure to download models.", comment: "Model repo name warning message")
                    isShowAlertToast = true
                }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                TextField("", text: $whisperService.settings.repoName)
                    .disabled(!isEditingRepoName)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(isEditingRepoName ? .primary : .secondary)
                Button{
                    isEditingRepoName.toggle()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(Color.successGreen)
                }
                .buttonStyle(.plain)
            }
            .toast(isPresenting: $isShowAlertToast, duration: 10.0) {
                AlertToast(displayMode: .alert, type: .regular, title: toastMessage)
            }
            /*
            .alert("Toast", isPresented: $isShowAlertToast) {
                Button("OK") {
                    isShowAlertToast = false
                }
                .padding()
            } message: {
                Text(toastMessage)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            */
            
            //TextField("Model Repo name", text: $whisperService.settings.repoName)
            //    .textFieldStyle(.roundedBorder)  // 圆角边框样式
            
            
            VStack(alignment: .leading) {
                /*
                TextField(
                    "Fallback Count", value: $whisperService.settings.fallbackCount,
                    formatter: NumberFormatter()
                )
                .textFieldStyle(.roundedBorder)  // 圆角边框样式
                */

                Slider(value: Binding(
                    get: { Double(whisperService.settings.fallbackCount) },
                    set: { whisperService.settings.fallbackCount = Int($0) }
                ), in: 0...15, step: 1) {
                    HStack {
                        Text(NSLocalizedString("Fallback Count", comment: "Fallback count slider label"))
                        Spacer()
                        Text(String(format: "%d", whisperService.settings.fallbackCount))
                            .bold()
                    }
                }

                Text(NSLocalizedString("The number of fallback models to use.", comment: "Fallback count description"))
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Slider(value: $whisperService.settings.temperatureStart, in: 0.0...2.0, step: 0.1) {
                    HStack {
                        Text(NSLocalizedString("Temperature Start", comment: "Temperature start slider label"))
                        Spacer()
                        Text(String(format: "%.1f", whisperService.settings.temperatureStart))
                            .bold()
                            
                    }
                }
                Text(NSLocalizedString("Regulates randomness: lower values ensure deterministic consistency, while higher values increase output variety and diversity.", comment: "Temperature start description"))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .italic()
            }

            VStack {
                Slider(value: $whisperService.settings.silenceThreshold, in: 0.1...1.0, step: 0.1) {
                    HStack {
                        Text(NSLocalizedString("Silence Threshold", comment: "Silence threshold slider label"))
                        Spacer()
                        Text(String(format: "%.1f", whisperService.settings.silenceThreshold))
                            .bold()
                    }
                }
                Text(NSLocalizedString("Controls the threshold for silence detection. Lower values will detect more silence, while higher values will detect less silence.", comment: "Silence threshold description"))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .italic()
            }

            Picker(NSLocalizedString("Encoder Compute Units", comment: "Encoder compute units picker label"), selection: $whisperService.settings.encoderComputeUnits)
            {
                Text(NSLocalizedString("All", comment: "All compute units option")).tag(MLComputeUnits.all)
                Text(NSLocalizedString("CPU Only", comment: "CPU only compute units option")).tag(MLComputeUnits.cpuOnly)
                Text(NSLocalizedString("CPU and GPU", comment: "CPU and GPU compute units option")).tag(MLComputeUnits.cpuAndGPU)
                Text(NSLocalizedString("CPU and ANE", comment: "CPU and ANE compute units option")).tag(MLComputeUnits.cpuAndNeuralEngine)
            }
            .pickerStyle(.menu)  // 默认的下拉菜单风格

            Picker(NSLocalizedString("Decoder Compute Units", comment: "Decoder compute units picker label"), selection: $whisperService.settings.decoderComputeUnits)
            {
                Text(NSLocalizedString("All", comment: "All compute units option")).tag(MLComputeUnits.all)
                Text(NSLocalizedString("CPU Only", comment: "CPU only compute units option")).tag(MLComputeUnits.cpuOnly)
                Text(NSLocalizedString("CPU and GPU", comment: "CPU and GPU compute units option")).tag(MLComputeUnits.cpuAndGPU)
                Text(NSLocalizedString("CPU and ANE", comment: "CPU and ANE compute units option")).tag(MLComputeUnits.cpuAndNeuralEngine)
            }
            .pickerStyle(.menu)  // 默认的下拉菜单风格

            
 

        } header: {
            Text(NSLocalizedString("Model", comment: "Model settings section header"))
        }
    }
}

struct SettingsAudioView: View {
    @AppStorage("selectedAudioSource") private var selectedAudioSource: String = "Built-in Microphone"
    @AppStorage("isRecordToFile") private var isRecordToFile: Bool = false
    @AppStorage("autoRecordingPath") private var autoRecordingPath: String = ""
    @AppStorage("exportPath") private var exportPath: String = ""

    var body: some View {
        Section {
            /*
            Picker("Audio Input", selection: $selectedAudioSource) {
                Text("Built-in Microphone").tag("Built-in Microphone")
                Text("External Microphone").tag("External Microphone")
            }
            .pickerStyle(.menu)  // 默认的下拉菜单风格
            */
            
            Toggle(NSLocalizedString("Auto Recording to File", comment: "Auto recording to file toggle label"), isOn: $isRecordToFile)
            .toggleStyle(.switch)  // MacOS风格的开关

            HStack {
                TextField(NSLocalizedString("Record File Folder", comment: "Record file folder textfield label"), text: $autoRecordingPath)
                    .textFieldStyle(.roundedBorder)  // 圆角边框样式

                Button(action: {
                    let folderURL = selectFolderURL(
                        initialDirectory: URL(fileURLWithPath: autoRecordingPath))
                    autoRecordingPath = folderURL?.path ?? autoRecordingPath
                }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
            }    

        } header: {
            Text(NSLocalizedString("Audio", comment: "Audio settings section header"))
        }
        .onAppear {
            print("@@@DEBUG0 Auto recording path: \(autoRecordingPath)")
            if autoRecordingPath == "" || !FileManager.default.fileExists(atPath: autoRecordingPath) {
                if exportPath == "" || !FileManager.default.fileExists(atPath: exportPath) {
                    let publicDocumentsDirectoryURL = FileManager.default.urls(
                        for: .documentDirectory, in: .userDomainMask
                    ).first!
                    autoRecordingPath =
                        publicDocumentsDirectoryURL.appendingPathComponent("transee_export/recordfiles").path
                } else {
                    autoRecordingPath = URL(fileURLWithPath: exportPath).appendingPathComponent("recordfiles").path
                }
                print("@@@DEBUG1 Auto recording path: \(autoRecordingPath)")
            } else {
                print("@@@DEBUG2: Auto recording path: \(autoRecordingPath)")
            }
        }
        //.padding()
        //.formStyle(.grouped) // 将 Form 呈现为分组样式，在 macOS 上有卡片效果
    }
}

struct SettingsExportView: View {
    //@EnvironmentObject var whisperService: WhisperService
    @AppStorage("exportFormat") private var exportFormat: ExportFormat = ExportFormat.txt
    @AppStorage("exportPath") private var exportPath: String = ""

    var body: some View {
        Section {
            Picker(NSLocalizedString("Export Format", comment: "Export format picker label"), selection: $exportFormat) {
                Text(NSLocalizedString("Text", comment: "Text export format")).tag(ExportFormat.txt)
                Text(NSLocalizedString("SRT", comment: "SRT export format")).tag(ExportFormat.srt)
                Text(NSLocalizedString("ASS", comment: "ASS export format")).tag(ExportFormat.ass)
                Text(NSLocalizedString("JSON", comment: "JSON export format")).tag(ExportFormat.json)
            }
            .pickerStyle(.segmented)  // 分段选择器

            HStack {
                TextField(NSLocalizedString("Export Folder", comment: "Export folder textfield label"), text: $exportPath)
                    .textFieldStyle(.roundedBorder)  // 圆角边框样式

                Button(action: {
                    let folderURL = selectFolderURL(
                        initialDirectory: URL(fileURLWithPath: exportPath))
                    exportPath = folderURL?.path ?? exportPath
                }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
            }

        } header: {
            Text(NSLocalizedString("Export", comment: "Export settings section header"))
        }
        .onAppear {
            print("@@@DEBUG0 Export path: \(exportPath)")
            if exportPath == "" || !FileManager.default.fileExists(atPath: exportPath) {
                let publicDocumentsDirectoryURL = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first!
                exportPath =
                    publicDocumentsDirectoryURL.appendingPathComponent("transee_export").path
                if !FileManager.default.fileExists(atPath: exportPath) {
                    try? FileManager.default.createDirectory(
                        atPath: exportPath, withIntermediateDirectories: true, attributes: nil)
                }
                print("@@@DEBUG1 Export path: \(exportPath)")
            } else {
                print("@@@DEBUG2: Export path: \(exportPath)")
            }
        }
        //.padding()
        //.formStyle(.grouped) // 将 Form 呈现为分组样式，在 macOS 上有卡片效果
        //.fixedSize(horizontal: false, vertical: true)
        //.frame(maxWidth: .infinity)

    }
}

struct SettingsAboutView: View {
    @EnvironmentObject var whisperService: WhisperService
    @State private var showHiddenSettings = false
    @State private var copyrightTapCount = 0

    private var appVersionString: String {
        let shortVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.isEmpty == false ? shortVersion : nil,
                buildVersion?.isEmpty == false ? buildVersion : nil) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        case let (nil, build?):
            return build
        default:
            return "—"
        }
    }

    var body: some View {
        Section {
            //VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Version", comment: "Version label"))
                Spacer()
                Text(appVersionString)
            }

            HStack {
                Text(NSLocalizedString("Copyright", comment: "Copyright label"))
                Spacer()
                Button {
                    guard !showHiddenSettings else { return }
                    copyrightTapCount += 1
                    if copyrightTapCount >= 5 {
                        showHiddenSettings = true
                    }
                } label: {
                    Text("© 2026 Magpie Software")
                }
                .buttonStyle(.plain)
            }

            if let url = URL(string: "https://www.magpieai.app/user-agreement") {
                Link(NSLocalizedString("Open Source License", comment: "Open source license link of third party"), destination: url)
            }

            if let url = URL(string: "https://www.magpieai.app/user-agreement") {
                Link(NSLocalizedString("Terms of Service and Privacy Policy", comment: "Terms of service and privacy policy link"), destination: url)
            }

            if let url = URL(string: "mailto:magpieiot@gmail.com") {
                Link(NSLocalizedString("Contact Us", comment: "Contact us link"), destination: url)
            }

            if showHiddenSettings {

                

            }

            
 

        } header: {
            Text(NSLocalizedString("About", comment: "About settings section header"))
        }

        if showHiddenSettings {
            Section {
                HStack {
                    Text(NSLocalizedString("Scan Local Model", comment: "Scan local model label"))
                    // Open Model Folder Button
                    Spacer()
                    Button(NSLocalizedString("Scan", comment: "Scan button label")) {
                        Task {
                            await whisperService.modelManager.importLocalModel()
                        }
                    }   
                }

                HStack {
                    Text(NSLocalizedString("Import Local Model", comment: "Import local model label"))
                    // Open Model Folder Button
                    Spacer()
                    Button(NSLocalizedString("Open Folder", comment: "Open folder button label")) {
                        Task {
                            //await whisperService.modelManager.importLocalModel()
                        }
                    }   
                }

                HStack {
                    Text(NSLocalizedString("Model Folder", comment: "Model folder label"))
                    // Open Model Folder Button
                    Spacer()
                    Button(NSLocalizedString("Open Model Folder", comment: "Open model folder button label")) {
                        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                        let documentsDirectory = paths[0]
                        if let url = URL(string: "file://" + documentsDirectory.path + "/" + whisperService.modelManager.getModelStoragePath()) {
                            NSWorkspace.shared.open(url)
                        }
                    }   
                }

                HStack {
                    Spacer()
                    Button(NSLocalizedString("Clear Settings", comment: "Clear settings button label")) {
                        // 检查更新的逻辑
                        clearSettings()
                    }
                    .buttonStyle(.bordered)
                }
                
            } header: {
                Text(NSLocalizedString("Hidden Settings", comment: "Hidden settings section header"))
            }
        }
        

        //.padding()
    }

    func clearSettings() {
        // 清除所有 AppStorage 中的设置
        // 或遍历删除（更彻底）
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize() // 确保立即写入磁盘
        }
        print("@@@DEBUG: Clear All User Default Settings")
        print("hasCompletedOnboarding: \(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))")
    }
}


#Preview {
    SettingsGeneralView()
}

#Preview {
    SettingsAppearanceView()
}

#Preview {
    SettingsModelView()
        .environmentObject(WhisperService())
}

#Preview {
    SettingsExportView()
}

#Preview {
    SettingsAboutView()
}

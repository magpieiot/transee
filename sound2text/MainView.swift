//
//  MainView.swift
//  sound2text
//
//  Created by gavanwang on 8/19/25.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AlertToast
@preconcurrency import WhisperKit

// MARK: - 常量定义
private enum Constants {
    static let appName = "Sound2Text"
    static let verticalPadding: CGFloat = 16.0
    static let horizontalPadding: CGFloat = 16.0
}

enum MainCategory: String, CaseIterable, Identifiable {
    case localfile = "File"
    case livemic = "Live"
    case history = "History"
    case aimodels = "Models"
    
    var localizedDisplayName: String {
        switch self {
        case .localfile:
            return NSLocalizedString("File", comment: "File category")
        case .livemic:
            return NSLocalizedString("Live", comment: "Live category")
        case .history:
            return NSLocalizedString("History", comment: "History category")
        case .aimodels:
            return NSLocalizedString("Models", comment: "Models category")
        }
    }

    var id: String { self.rawValue }
    var symbolName: String {
        switch self {
        case .localfile: return "music.note"
        case .livemic: return "mic"
        case .history: return "clock"
        case .aimodels: return "circle.hexagongrid"
        }
    }
    var isAvailable: Bool {
        switch self {
            case .localfile: return true
            case .livemic: return true
            case .history: return true
            case .aimodels: return true
        }
    }
}

// 视图工作状态
enum TranscribeFileViewState {
    case idle  // 空闲状态
    case selectFiles  // 选择文件状态
    case ready  // 待命状态
    case playing  // 播放状态，包括暂停
    case transcribing  // 转录状态，包括等待等等
    case transcribed  // 全部文件均转录完成状态
    case error  // 错误状态
    var symbolName: String {
        switch self {
        case .idle: return "questionmark.circle"
        case .selectFiles: return "doc.on.clipboard"
        case .ready: return "play.circle"
        case .playing: return "pause.circle"
        case .transcribing: return "clock"
        case .transcribed: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        }
    }
    var stateName: String {
        switch self {
        case .idle: return NSLocalizedString("Idle", comment: "Idle state")
        case .selectFiles: return NSLocalizedString("Select Files", comment: "Select files state")
        case .ready: return NSLocalizedString("Ready", comment: "Ready state")
        case .playing: return NSLocalizedString("Playing", comment: "Playing state")
        case .transcribing: return NSLocalizedString("Transcribing", comment: "Transcribing state")
        case .transcribed: return NSLocalizedString("Transcribed", comment: "Transcribed state")
        case .error: return NSLocalizedString("Error", comment: "Error state")
        }
    }
}

// 选中的音频文件结构
struct SelectedAudioFile: Hashable, Identifiable {
    let id = UUID()
    let fileUrl: URL
    let fileBaseName: String
    let fileSize: Int
    let fileType: UTType
    var mediaType: MediaType
    var fileDuration: Double
    var sampleRate: Double
    var isVideo: Bool
    var isSupportFormat: Bool
    var isPlayable: Bool
    var currentPlayingPosition: Double = 0.0 {
        didSet {
            if currentPlayingPosition != oldValue {
                print("@@@DEBUG: currentPlayingPosition: \(currentPlayingPosition)")
            }
        }
    }
    // 音频文件状态，默认为空闲状态
    var fileState: AudioFileState = .idle
    // 转写状态，默认为正在转换音频
    var transcriptionState: TranscriptionState = .convertingAudio
    var transcriptionSegments: [TranscriptionSegment] = []
    var transcrDuration: Double = 0.0

    init(
        fileUrl: URL, fileBaseName: String, fileSize: Int, fileType: UTType, mediaType: MediaType,
        fileDuration: Double = 0, isVideo: Bool = false, isSupportFormat: Bool = true,
        isPlayable: Bool = true
    ) {
        self.fileUrl = fileUrl
        self.fileBaseName = fileBaseName
        self.fileSize = fileSize
        self.fileType = fileType
        self.mediaType = mediaType
        self.fileDuration = fileDuration
        self.sampleRate = 0.0
        self.isVideo = isVideo
        self.isSupportFormat = isSupportFormat
        self.isPlayable = isPlayable
    }
}

// MARK: - 主视图
struct MainView: View {
    @StateObject var audioPlayer = AudioPlayerManager()
    @StateObject var viewModel = MainViewModel()
    @StateObject var historyManager = HistoryManager()
    @EnvironmentObject var whisperService: WhisperService
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var appStateManager: AppStateManager
    @AppStorage("exportPath") var exportPath: String = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationSplitView {
            MainSideBarView(viewModel: viewModel)
                //.background(Color.sidebarBackground)
                //.background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                .navigationSplitViewColumnWidth(min: 144, ideal: 144, max: 144)
        } detail: {
            MainDetailView(viewModel: viewModel)
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toast(isPresenting: $viewModel.showToast) {
            viewModel.alertToast
        }
        .sheet(
            isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { _ in }
            )
        ) {
            OnboardingView()
                .environmentObject(whisperService)
                .frame(width: 600, height: 450)
                .fixedSize()
                //.interactiveDismissDisabled(true)
                .background(SheetWindowSizeLock(size: NSSize(width: 600, height: 450)))
        }
        .onAppear {
            if exportPath != "" {
                exportPath = ""
            }

            print("@@@DEBUG: MainView onAppear, hasCompletedOnboarding: \(hasCompletedOnboarding)")
            //whisperService.modelManager.fetchModels()
            // 初始化时设置文档访问权限
            if hasCompletedOnboarding {
                Task { @MainActor in
                    if let url = await permissionManager.ensureDocumentsFolderAccess() {
                        viewModel.publicDocumentsDirectoryURL = url
                        if exportPath == "" || !FileManager.default.fileExists(atPath: exportPath) {
                            exportPath = setupDefaultExportPath(publicDocumentsURL: url)
                        }
                    }
                }
                // 检查本地模型列表，如果没有本地模型，则直接调转到模型下载界面
                if whisperService.modelManager.localModels.isEmpty || whisperService.settings.selectedModel == "" || !whisperService.modelManager.localModels.contains(where: { $0 == whisperService.settings.selectedModel })
                {
                    viewModel.selectedCategory = .aimodels
                }
                else {
                    print("@@@DEBUG: Now Model being selected is : \(whisperService.settings.selectedModel)")
                    viewModel.selectedCategory = .localfile
                    Task {
                        await whisperService.loadSelectedModel()    // 加载选中的模型
                        
                        // 检查是否选择了语言，如果没有选择，从模型支持的语言中找到符合 App 默认语言的那个，如果找不到，则设置为"English"
                        if whisperService.settings.selectedLanguage.isEmpty {
                            let availableLanguages = whisperService.modelManager.availableLanguages
                            let preferredLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
                            
                            // 尝试找到与系统默认语言匹配的语言
                            if let matchedLanguage = availableLanguages.first(where: { lang in
                                let displayString = LanguageWhisperResources.getDisplayString(for: lang)
                                return displayString.localizedCaseInsensitiveContains(preferredLanguageCode) ||
                                       lang.localizedCaseInsensitiveContains(preferredLanguageCode)
                            }) {
                                whisperService.settings.selectedLanguage = matchedLanguage
                            } else if let englishLanguage = availableLanguages.first(where: {
                                $0.localizedCaseInsensitiveContains("english") || $0 == "en"
                            }) {
                                // 如果没有找到匹配的语言，则设置为 English
                                whisperService.settings.selectedLanguage = englishLanguage
                            } else if !availableLanguages.isEmpty {
                                // 如果 English 也找不到，使用第一个可用语言
                                whisperService.settings.selectedLanguage = availableLanguages[0]
                            }
                        }
                    }
                }
            } else{
                print("@@@DEBUG: MainView onAppear has first time run, show onboarding")
                print("@@@DEBUG: Now Model being selected is : \(whisperService.settings.selectedModel)")
            }
        }
        .environmentObject(audioPlayer)
        .environmentObject(historyManager)
        .onReceive(whisperService.modelManager.$errorMessage) { errorMessage in
            if let message = errorMessage {
                viewModel.alertToast = AlertToast(displayMode: .hud, type: .error(.red), title: "Error", subTitle: message)
                // 重置错误消息，以免重复触发（取决于 UI 逻辑，但通常这样比较稳妥）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    whisperService.modelManager.errorMessage = nil
                }
            }
        }
    }
}

#if os(macOS)
private struct SheetWindowSizeLock: NSViewRepresentable {
    let size: NSSize

    final class Coordinator {
        var resizeObserver: Any?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }

            Self.apply(size, to: window)

            if context.coordinator.resizeObserver == nil {
                context.coordinator.resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    Self.apply(size, to: window)
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.resizeObserver = nil
        }
    }

    private static func apply(_ size: NSSize, to window: NSWindow) {
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.styleMask.remove(.resizable)
    }
}
#endif

// MARK: - 视图模型
@MainActor
class MainViewModel: ObservableObject {
    @Published var selectedCategory: MainCategory = .localfile
    @Published var selectedAudioFiles: [SelectedAudioFile] = []
    @Published var transcribeFileViewState: TranscribeFileViewState = .idle
    @Published var isLiveRecordToFile: Bool = false
    @Published var transcribeLiveResult: [TranscriptionSegment] = []
    @Published var lastDropError: String?  // 用于显示拖拽时的错误信息
    @Published var showToast: Bool = false
    @Published var alertToast = AlertToast(type: .loading) {
        didSet {
            showToast.toggle()
        }
    }

    @State private var errorMessage: String?
    @State private var isShowFilesSelectSheet = false
    @State private var isShowSettingsSheet = false

    var publicDocumentsDirectoryURL: URL?

    private var currentKeyWindow: NSWindow? {
        NSApp.keyWindow
    }

    func selectFiles() async {
        isShowFilesSelectSheet = true
        errorMessage = nil

        do {
            let urls = try await openFilePanelAsync(currentKeyWindow: currentKeyWindow)
            selectedAudioFiles = urls.map { url in
                SelectedAudioFile(
                    fileUrl: url,
                    fileBaseName: url.lastPathComponent,
                    fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                    fileType: UTType(filenameExtension: url.pathExtension) ?? .audio,
                    mediaType: .audio,
                )
            }
            print(
                "@@@DEBUG: Selected Files: \(selectedAudioFiles.map { $0.fileBaseName }), Type:\(selectedAudioFiles.map { $0.fileType.preferredFilenameExtension })"
            )
        } catch {
            errorMessage = error.localizedDescription
            print("@@@DEBUG: File Selected Fail!\(error)")
        }

        isShowFilesSelectSheet = false
    }

    func showHistory() {
        // TODO: 实现历史记录功能
        self.selectedCategory = .history
    }

    func showAIModels() {
        // TODO: 实现历史记录功能
        self.selectedCategory = .aimodels
    }
}

// MARK: - 侧边栏视图
struct MainSideBarView: View {
    @ObservedObject var viewModel: MainViewModel
    @EnvironmentObject var whisperService: WhisperService

    var body: some View {
        VStack(alignment: .leading) {
            //headerView
            mainButtonsList
            Spacer()
            bottomButtonsList
        }
    }

    // 侧边栏顶部标题
    private var headerView: some View {
        HStack {
            Image("transcribe")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundStyle(.tint)
            Text(Constants.appName)
                .font(.headline)
                .fontWeight(.medium)
        }
        .padding(.vertical, Constants.verticalPadding)
        .padding(.horizontal, Constants.horizontalPadding)
    }

    private var mainButtonsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(MainCategory.allCases) { category in

            SideBarButton(
                title: category.localizedDisplayName,
                icon: category.symbolName,
                minWidth: 80,
                backgroundColor: Color("twIndigo600"),
                isActive: (viewModel.selectedCategory == category),
                isAvailable: category.isAvailable
            ) {
                viewModel.selectedCategory = category
            }
            }
        }
        .padding()
    }

    private var bottomButtonsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SideBarButton(
                title: NSLocalizedString("Setting", comment: "Setting button title"),
                icon: "gear",
                minWidth: 80,
            ) {
                NSApp.sendAction(#selector(AppDelegate.showSettingsModal), to: nil, from: nil)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.bottom, Constants.verticalPadding)
    }
}

// MARK: - 详情视图

struct MainDetailView: View {
    @ObservedObject var viewModel: MainViewModel
    @EnvironmentObject var whisperService: WhisperService

    var body: some View {
        ZStack {
            TranscribeFileView(viewModel: viewModel)
                .opacity(viewModel.selectedCategory == .localfile ? 1.0 : 0.0)
                .allowsHitTesting(viewModel.selectedCategory == .localfile)

            TranscribeliveView(viewModel: viewModel)
            //SpeechRecognitionDemoView()
                .opacity(viewModel.selectedCategory == .livemic ? 1.0 : 0.0)
                .allowsHitTesting(viewModel.selectedCategory == .livemic)
            
            //UnderDevelopmentView()
            //    .opacity(viewModel.selectedCategory == .livemic ? 1.0 : 0.0)
            //    .allowsHitTesting(viewModel.selectedCategory == .livemic)
            
            HistoryView(isActive: (viewModel.selectedCategory == .history))
                .opacity(viewModel.selectedCategory == .history ? 1.0 : 0.0)
                .allowsHitTesting(viewModel.selectedCategory == .history)

            ModelSettingView()
                .opacity(viewModel.selectedCategory == .aimodels ? 1.0 : 0.0)
                .allowsHitTesting(viewModel.selectedCategory == .aimodels)
        }
        .toolbarRole(.editor)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            switch viewModel.selectedCategory {
                case .localfile:
                    ToolbarItem(placement: .status) {
                        MainViewModelStatusBar()
                    }
                    
                case .livemic:
                    ToolbarItem(placement: .status) {
                        MainViewModelStatusBar()
                    }

                //case .history:
                    /*
                    ToolbarItem(placement: .automatic) {
                        Text(NSLocalizedString("History", comment: "History toolbar title"))
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                    }
                    */
                    /*
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            viewModel.sortOrder = viewModel.sortOrder == .descending ? .ascending : .descending
                        }) {
                            Image(systemName: viewModel.sortOrder == .descending ? "clockwise" : "counterclockwise")
                                .font(.title2)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.sortOrder == .descending ? "Sorted by Newest First" : "Sorted by Oldest First")
                    }
                     */
                    
                //case .aimodels:
                    
                    /*
                    ToolbarItem(placement: .automatic) {
                        Text(NSLocalizedString("Local Models", comment: "Local models toolbar title"))
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                    }
                    */
                default:
                    ToolbarItem(placement: .primaryAction) {
                        Text("")
                    }
            }
            /*
            if viewModel.selectedCategory == .history {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel.sortOrder = viewModel.sortOrder == .descending ? .ascending : .descending
                    }) {
                        Image(systemName: viewModel.sortOrder == .descending ? "clockwise" : "counterclockwise")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.sortOrder == .descending ? "Sorted by Newest First" : "Sorted by Oldest First")
                }
            }
            else {
                ToolbarItem(placement: .primaryAction) {
                    Text("")
                }
            }
             */
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    struct MainViewModelStatusBar: View {
        @EnvironmentObject var whisperService: WhisperService
        @State private var backgroundColor: Color = .clear

        var body: some View {
            if whisperService.getSelectedModel() != "" {
                let selectedLanguage = whisperService.settings.selectedLanguage
                HStack(alignment: .center) {
                    if whisperService.modelManager.modelState == .loading {
                        LoadingRing(size: 14, lineWidth: 4, colors: [.successGreen, .babyBlue])
                            .padding(.leading, 16.0)
                    } else {
                        Circle()
                            .fill(backgroundColor(for: whisperService.modelManager.modelState))
                            .frame(width: 14, height: 14)
                            .padding(.leading, 16.0)
                    }
                    Text("\(NSLocalizedString("Model", comment: "Model label")): \(whisperService.getSelectedModel())")  //viewModel.selectedCategory.rawValue)
                        .font(.headline)
                        .padding(.horizontal, 16)
                    
                     Text("\(NSLocalizedString("Language", comment: "Language label")): \(LanguageWhisperResources.getDisplayString(for: selectedLanguage))")
                         .font(.headline)
                         .padding(.horizontal, 16)
                     
                     Spacer()
                 }
             } else {
                 Text(NSLocalizedString("No Model Selected", comment: "No model selected message"))
                     .font(.headline)
                     .padding(.horizontal, 16)
             }
        }

        private func backgroundColor(for modelState: ModelState) -> Color {
            switch modelState {
            case .loading, .prewarming, .prewarmed:
                return .yellow
            case .loaded:
                return .successGreen
            case .downloaded, .downloading:
                return .babyBlue
            default:
                return .clear
            }
        }
    }

    struct MainViewModelStatusBar2: View {
        @EnvironmentObject var whisperService: WhisperService
        @State private var backgroundColor: Color = .clear

        var body: some View {
            if whisperService.getSelectedModel() != "" {
                HStack(alignment: .center) {
                    if whisperService.modelManager.modelState == .loading {
                        LoadingRing(size: 14, lineWidth: 4, colors: [.successGreen, .babyBlue])
                            .padding(.leading, 16.0)
                    } else {
                        Circle()
                            .fill(backgroundColor(for: whisperService.modelManager.modelState))
                            .frame(width: 14, height: 14)
                            .padding(.leading, 16.0)
                    }
                    Text("Model: Apple Speech Recognition")  //viewModel.selectedCategory.rawValue)
                        .font(.headline)
                        .padding(.horizontal, 16)
                    
                     Text("Language: Chinese")
                         .font(.headline)
                         .padding(.horizontal, 16)
                     
                     Spacer()
                 }
             } else {
                 Text(NSLocalizedString("No Model Selected", comment: "No model selected message"))
                     .font(.headline)
                     .padding(.horizontal, 16)
             }
        }

        private func backgroundColor(for modelState: ModelState) -> Color {
            switch modelState {
            case .loading, .prewarming, .prewarmed:
                return .yellow
            case .loaded:
                return .successGreen
            case .downloaded, .downloading:
                return .babyBlue
            default:
                return .clear
            }
        }
    }

}

// MARK: - 预览
#Preview {
    MainView()
        .frame(width: 1200, height: 600)
        .environmentObject(WhisperService())
}

#Preview {
    MainSideBarView(viewModel: MainViewModel())
        .environmentObject(WhisperService())
}

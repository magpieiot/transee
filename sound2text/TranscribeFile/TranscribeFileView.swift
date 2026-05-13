//
//  TranscribeLocalFileView.swift
//  sound2text
//
//  Created by gavanwang on 8/29/25.
//

import AVFoundation
import AlertToast
import Combine
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import WhisperKit

//
// 音频文件状态枚举
enum AudioFileState {
    case idle  // 空闲状态
    case playing  // 正在播放
    case paused  // 暂停播放
    case stopped  // 已停止
    case transcribing  // 正在转录
    case transcribed  // 转录完成
    case waiting  // 等待转录
    case error  // 错误状态

    // 获取状态描述
    var description: String {
        switch self {
        case .idle: return NSLocalizedString("Idle", comment: "Idle state")
        case .playing: return NSLocalizedString("Playing", comment: "Playing state")
        case .paused: return NSLocalizedString("Paused", comment: "Paused state")
        case .stopped: return NSLocalizedString("Stopped", comment: "Stopped state")
        case .transcribing: return NSLocalizedString("Transcribing", comment: "Transcribing state")
        case .transcribed: return NSLocalizedString("Transcribed", comment: "Transcribed state")
        case .waiting: return NSLocalizedString("Waiting", comment: "Waiting state")
        case .error: return NSLocalizedString("Error", comment: "Error state")
        }
    }
}

struct TranscribeFileView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isPlayorPause = false
    @State private var isTranscribing = false
    @State private var currentProcessingFile: SelectedAudioFile?
    @State private var currentClickFile: SelectedAudioFile?
    @State private var isShowTranscriptionTable: Bool = false
    @State private var isExportComplete: Bool = false
    @State private var isHovering: Bool = false
    @State private var isDropping: Bool = false
    @State private var isTargeted: Bool = false  // 绑定到 DropDelegate
    @State private var isDroppedFileInvaild: Bool = false
    @State private var isHaveCompletedResult: Bool = false
    @State private var isShowingBackAlert: Bool = false
    @State private var transcribeTimer = Timer.publish(every: 1.0, on: .main, in: .common)
        .autoconnect()

    var dropDelegate: FileDropDelegate {
        FileDropDelegate(isTargeted: $isTargeted, viewModel: viewModel)
    }

    @AppStorage("exportPath") var exportPath: String = ""
    @AppStorage("exportFormat") var exportFormat: ExportFormat = ExportFormat.txt

    @EnvironmentObject var whisperService: WhisperService
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        switch viewModel.transcribeFileViewState {
        case .idle:
            emptyFilesView()
        case .selectFiles, .ready, .playing, .transcribing, .transcribed:
            filesListView()
        case .error:
            emptyFilesView()
        }
    }

    // 文件列表视图
    func filesListView() -> some View {
        GeometryReader { geometry in
            VStack {
                if !viewModel.selectedAudioFiles.isEmpty {
                    HStack {
                        Button(action: {
                            // 返回按钮点击逻辑
                            if isHaveCompletedResult {
                                isShowingBackAlert = true
                            } else {
                                viewModel.transcribeFileViewState = .idle
                                viewModel.selectedAudioFiles.removeAll()
                                currentProcessingFile = nil
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.accentBrandPrimary)
                                .font(.title)
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 16)

                        Text("\(NSLocalizedString("Selected Files", comment: "Selected files label")): " + String(viewModel.selectedAudioFiles.count))
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.leading)
                        Spacer()
                        switch viewModel.transcribeFileViewState {
                            case .idle, .selectFiles, .ready, .playing, .transcribing:
                                SideBarButton(
                                    title: isTranscribing ? NSLocalizedString("Stop", comment: "Stop button label") : NSLocalizedString("Transcribe", comment: "Transcribe button label"),
                                    icon: isTranscribing ? "stop.fill" : "play.fill",
                                    minWidth: 144,
                                    maxWidth: 144,
                                    alignment: .center,
                                    backgroundColor: isTranscribing ? Color.red : Color.accentBrandPrimary,
                                    isActive: true,
                                    action: {
                                        Task {
                                            if isTranscribing {
                                                // 停止转录文件
                                                isTranscribing = false
                                                transcriptionStop()
                                            } else {
                                                // 开始转录文件
                                                isTranscribing = true
                                                viewModel.transcribeFileViewState = .transcribing
                                                isHaveCompletedResult = false
                                                for index in viewModel.selectedAudioFiles.indices {
                                                    viewModel.selectedAudioFiles[index].fileState = .waiting
                                                }
                                                await transcriptionStart(selectedAudioFiles: viewModel.selectedAudioFiles)
                                            }
                                        }
                                    }
                                )
                            case .transcribed:
                                SideBarButton(
                                    title: NSLocalizedString("Export", comment: "Export button label"),
                                    icon: "square.and.arrow.up.on.square",
                                    minWidth: 64,
                                    maxWidth: 122,
                                    alignment: .center,
                                    backgroundColor: Color.accentBrandPrimary,
                                    isActive: true,
                                    action: {
                                        Task {
                                            // Default to SRT format as an example
                                            await exportTranscription()
                                            isExportComplete = true
                                        }
                                    }
                                )
                            case .error:
                                SideBarButton(
                                    title: NSLocalizedString("Error", comment: "Error button label"),
                                    icon: "exclamationmark.triangle.fill",
                                    minWidth: 64,
                                    maxWidth: 122,
                                    backgroundColor: Color.crayolaRed,
                                    isActive: true,
                                    action: {
                                        //
                                    }
                                )
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }

                List {
                    Section {
                        ForEach($viewModel.selectedAudioFiles) { $fileData in
                            FileInformationBar(
                                viewModel: viewModel,
                                currentProcessingFile: $currentProcessingFile,
                                currentClickFile: $currentClickFile,
                                isShowTranscriptionTable: $isShowTranscriptionTable,
                                fileData: fileData,
                            )
                            .padding(.vertical, 8)
                            .padding(.trailing, 8)
                            .onAppear {
                                Task {
                                    //let index = viewModel.selectedAudioFiles.firstIndex(where: { $0 == fileData }) ?? 0
                                    let (duration, sampleRate) = await calculateAudioDuration(from: fileData.fileUrl)
                                    fileData.fileDuration = duration
                                    fileData.sampleRate = sampleRate
                                    fileData.isSupportFormat = (duration > 0.0)
                                    let mediaType = try await identifyMediaFileType(at: fileData.fileUrl)
                                    fileData.isPlayable = (mediaType == .audio || mediaType == .audioAndVideo)
                                    fileData.mediaType = mediaType
                                    print(
                                        "@@@DEBUG: 转写进度更新7: file Name: \(fileData.fileBaseName), Duration: \(fileData.fileDuration), SampleRate: \(fileData.sampleRate), MediaType: \(mediaType)"
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)

                if let playingFile = currentProcessingFile {
                    switch viewModel.transcribeFileViewState {
                        case .playing:
                            AudioPlayerBar(
                                playingUrl: playingFile.fileUrl, viewModel: viewModel, isPlayorPause: $isPlayorPause)
                        case .transcribing:
                            TranscribeFileStateBar(fileData: playingFile, isTranscribing: $isTranscribing)
                        default:
                            EmptyView()
                    }
                }
            }
            // 播放状态转换
            .onChange(of: viewModel.transcribeFileViewState) { oldValue, newValue in
                if newValue == .playing {
                    if let file = currentProcessingFile {
                        audioPlayer.loadAudio(from: file.fileUrl)
                        audioPlayer.play()
                        viewModel.transcribeFileViewState = .playing
                        isPlayorPause = true
                    }
                } else if newValue == .ready {
                    audioPlayer.stop()
                    viewModel.transcribeFileViewState = .ready
                    isPlayorPause = false
                }
            }
            .alert(NSLocalizedString("Confirm Return", comment: "Confirm return alert title"), isPresented: $isShowingBackAlert) {
                Button(NSLocalizedString("Cancel", comment: "Cancel button label"), role: .cancel) { }
                Button(NSLocalizedString("Return", comment: "Return button label"), role: .destructive) {
                    viewModel.transcribeFileViewState = .idle
                    viewModel.selectedAudioFiles.removeAll()
                    currentProcessingFile = nil
                    isHaveCompletedResult = false
                }
            } message: {
                Text(NSLocalizedString("Returning will lose the transcription results already obtained. Are you sure you want to return?", comment: "Confirm return message"))
            }
            .sheet(item: $currentClickFile, onDismiss: dismiss) { selected in
                let windowSize = CGSize(width: geometry.size.width - 64, height: geometry.size.height - 64)
                let url = selected.fileUrl
                if viewModel.selectedAudioFiles.contains(where: { $0.fileUrl == url }) {
                    TranscribeResultView(viewModel: viewModel, sourcefileUrl: url, windowSize: windowSize)
                } else {
                    Text("未选择文件或文件不存在, \(selected.fileBaseName)")
                }
            }
            .alert(NSLocalizedString("Export Completed", comment: "Export completed alert title"), isPresented: $isExportComplete) {
                Button("OK", role: .cancel) {
                    isExportComplete = false
                    viewModel.transcribeFileViewState = .idle
                    viewModel.selectedAudioFiles.removeAll()
                    currentProcessingFile = nil
                    isHaveCompletedResult = false
                }
            } message: {
                Text(NSLocalizedString("The files have been exported successfully. Press OK to return to home.", comment: "Export completed message"))
            }

        }
    }

    func dismiss() {
        currentClickFile = nil
    }

    // 空文件选择视图
    func emptyFilesView() -> some View {
        VStack {
            Spacer()  // 将内容推到垂直方向的中央或靠上

            VStack(spacing: 16) {  // 虚线框内部的内容
                Image(systemName: "doc.fill")  // 文件图标
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                    .overlay(
                        // 下载箭头叠加在文件图标上
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.headline)
                            .offset(x: 10, y: 10)  // 调整箭头位置
                            .foregroundColor(.gray)
                    )

                Text(NSLocalizedString("Drop audio or video files here", comment: "Drop files instruction"))
                    .font(.body)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("or", comment: "Or separator"))
                    .font(.footnote)
                    .foregroundColor(.secondary)

                SideBarButton(
                    title: NSLocalizedString("Choose Files", comment: "Choose files button label"), 
                    icon: nil,
                    alignment: .center,
                    labelColor: .white, 
                    backgroundColor: Color.accentBrandPrimary,
                    isActive: true,
                    isLoading: false,
                    isAvailable: true
                ) {
                    Task {
                        await viewModel.selectFiles()
                        if !viewModel.selectedAudioFiles.isEmpty {
                            viewModel.transcribeFileViewState = .selectFiles
                        }
                    }
                }

                /*
                Button(action: {
                    // 点击按钮的逻辑，例如打开文件选择器
                    Task {
                        await viewModel.selectFiles()
                        if !viewModel.selectedAudioFiles.isEmpty {
                            viewModel.transcribeFileViewState = .selectFiles
                        }
                    }

                }) {
                    Text("Choose Files")
                        .font(.body)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .foregroundColor(.white)
                }
                //.background(Color.gradientTechButton)
                .background(.gradientTechButton)
                .cornerRadius(.infinity)
                .shadow(color: .gray, radius: 3, x: 2, y: 2)
                */
            }
            .frame(maxWidth: .infinity)  // 让 VStack 宽度尽可能大
            .padding(40)  // 内部内容与虚线边框之间的间距
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isTargeted
                            ? (viewModel.lastDropError == nil ? Color.blue.opacity(0.1) : Color.red.opacity(0.1))
                            : (isHovering ? Color.accentBrandSecondary.opacity(0.5) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isTargeted ? (viewModel.lastDropError == nil ? Color.blue : Color.red) : Color.gray,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )
            )
            .padding(.horizontal, 30)  // 虚线框与屏幕边缘的间距
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
            // MARK: - 核心拖放修饰符
            .onDrop(of: [.fileURL], delegate: dropDelegate)
            /*
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropping) { providers in
                    // 当文件被放下时执行此闭包
                    print("@@@DEBUG: Dropped providers: \(providers.description)")
                    isDroppedFileInvaild = handleDroppedProviders(providers)
            
                    if isDroppedFileInvaild && !viewModel.selectedAudioFiles.isEmpty {
                            viewModel.transcribeFileViewState = .selectFiles
                            for files in viewModel.selectedAudioFiles {
                                    print("@@@DEBUG: Dropped file: \(files.fileUrl)")
                            }
                    }
            
                    return true // 返回 true 表示我们接受了拖放操作
            }
            */

            // 支持的格式文本
                Text(NSLocalizedString("Supported formats: mp3, m4a, aac, wav, aiff, mp4, mov", comment: "Supported formats description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)  // 与虚线框的间距

            Spacer()  // 将内容推到垂直方向的中央或靠下
        }
        .padding(.vertical)  // 整个界面内容的垂直填充
    }

    // 转录文件状态条 (Struct Wrapper)

    struct TranscribeFileStateBar: View {
        let fileData: SelectedAudioFile
        @EnvironmentObject var whisperService: WhisperService
        @Binding var isTranscribing: Bool
        @State private var isSpinning = false

        var body: some View {
            HStack(alignment: .center) {
                Image("transcribe")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        isSpinning
                            ? Animation.linear(duration: 2).repeatForever(autoreverses: false) : .default,
                        value: isSpinning
                    )
                    .padding(.trailing, 8)
                    .onAppear {
                        if isTranscribing {
                            isSpinning = true
                        }
                    }
                    .onChange(of: isTranscribing) { _, newValue in
                        isSpinning = newValue
                    }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(
                            whisperService.transcriptionEngine.currentText.replacingOccurrences(
                                of: whisperService.settings.initialPrompts.first?.prompt ?? "", with: "")
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .id("bottomID")  // 用于定位到底部
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 当实时文本变化时，自动滚动到最底部
                    .onChange(
                        of: whisperService.transcriptionEngine.currentText.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    ) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo("bottomID", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            //.cornerRadius(16)
            .background(.ultraThinMaterial)
            .frame(height: 88.0)
        }
    }

    // 音频播放条 (Struct Wrapper)
    struct AudioPlayerBar: View {
        let playingUrl: URL
        @ObservedObject var viewModel: MainViewModel
        @Binding var isPlayorPause: Bool
        @EnvironmentObject var audioPlayer: AudioPlayerManager

        @State private var isSpinning = false

        var body: some View {
            HStack(alignment: .center) {
                Image("vinylrecord3")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        isSpinning
                            ? Animation.linear(duration: 2).repeatForever(autoreverses: false) : .default,
                        value: isSpinning
                    )
                    .onAppear {
                        if isPlayorPause {
                            isSpinning = true
                        }
                    }
                    .onChange(of: isPlayorPause) { _, newValue in
                        isSpinning = newValue
                    }

                Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration) {
                    Text("")
                } minimumValueLabel: {
                    Text(audioPlayer.currentTimeString)
                } maximumValueLabel: {
                    Text(audioPlayer.durationString)
                }

                // 播放按钮
                Button(action: {
                    // 点击按钮的逻辑，播放
                    if viewModel.transcribeFileViewState == .playing && isPlayorPause {
                        // 点击暂停按钮，暂停播放
                        audioPlayer.pause()
                        isPlayorPause = false
                        if let index = viewModel.selectedAudioFiles.firstIndex(where: {
                            $0.fileUrl == playingUrl
                        }) {
                            viewModel.selectedAudioFiles[index].fileState = .paused
                        }
                    } else {
                        // 点击播放按钮，播放音频
                        audioPlayer.play()
                        isPlayorPause = true
                        if let index = viewModel.selectedAudioFiles.firstIndex(where: {
                            $0.fileUrl == playingUrl
                        }) {
                            viewModel.selectedAudioFiles[index].fileState = .playing
                        }
                    }
                }) {
                    Image(systemName: isPlayorPause ? "pause.circle" : "play.circle")
                        .foregroundColor(isPlayorPause ? Color.orange : Color.accentBrandPrimary)
                        .font(.title)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .cornerRadius(16)
            .background(.ultraThinMaterial)
            .frame(height: 64)
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let dispatchGroup = DispatchGroup()  // 用于等待所有异步加载完成
        for provider in providers {
            print("--- Analyzing new NSItemProvider ---")
            print("Registered types: \(provider.registeredTypeIdentifiers)")
            print(
                "Can load UTType.fileURL.identifier: \(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))"
            )
            print("Can load object ofClass URL.self: \(provider.canLoadObject(ofClass: URL.self))")
            // 优先从 file-url 类型读取（Finder 拖入文件的标准类型）
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {  // 检查是否可以加载为 URL
                dispatchGroup.enter()  // 进入 dispatch group，等待异步加载完成
                // 异步加载 URL，确保在主线程更新 UI
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    (item, error) in
                    let isItemData = item is Data
                    let resolvedURL: URL? = {
                        if let data = item as? Data {
                            return URL(dataRepresentation: data, relativeTo: nil)
                        }
                        return item as? URL
                    }()
                    let unexpectedItemDescription = resolvedURL == nil ? String(describing: item) : nil

                    DispatchQueue.main.async {  // 确保在主线程更新 UI
                        defer { dispatchGroup.leave() }
                        if let error = error {
                            print("Error loading file URL: \(error.localizedDescription)")
                            return
                        }
                        if let url = resolvedURL {
                            if isItemData {
                                print("Dropped file URL (Data->URL): \(url.path)")
                            } else {
                                print("Dropped file URL: \(url.path)")
                            }
                            viewModel.selectedAudioFiles.append(
                                SelectedAudioFile(
                                    fileUrl: url,
                                    fileBaseName: url.lastPathComponent,
                                    fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                                    fileType: UTType(filenameExtension: url.pathExtension) ?? .audio,
                                    mediaType: .audio,
                                ))
                        } else {
                            print("Unexpected item type for fileURL: \(unexpectedItemDescription ?? "nil")")
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {  // 兜底：对象读取为 URL
                dispatchGroup.enter()  // 进入 dispatch group，等待异步加载完成
                _ = provider.loadObject(ofClass: URL.self) { (url, error) in
                    DispatchQueue.main.async {
                        defer { dispatchGroup.leave() }
                        if let url = url {
                            print("Dropped file URL (object): \(url.path)")
                            viewModel.selectedAudioFiles.append(
                                SelectedAudioFile(
                                    fileUrl: url,
                                    fileBaseName: url.lastPathComponent,
                                    fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                                    fileType: UTType(filenameExtension: url.pathExtension) ?? .audio,
                                    mediaType: .audio,
                                ))
                        } else if let error = error {
                            print("Error loading file URL: \(error.localizedDescription)")
                        } else {
                            print("Provider returned no URL and no error.")
                        }
                    }
                }
            } else {
                // 如果是其他类型，你也可以尝试加载其他通用类型，例如 .text
                // 或者在这里打印一条消息，表示该 provider 无法加载为 URL
                print("Provider cannot load as URL: \(provider.registeredTypeIdentifiers)")
            }
        }
        dispatchGroup.notify(queue: .main) {
            // 所有文件都加载完成后，更新状态
            self.isDropping = false
        }
        return true  // 表明拖放操作已被处理
    }

    // 方法：transcriptionStart(selectedAudioFiles:)
    @MainActor
    func transcriptionStart(selectedAudioFiles: [SelectedAudioFile]) async {
        //var fileIndex: Int = 0
        print("!!!!---------------- Hello everyone, transcription is Start ----------------!!!!")
        isHaveCompletedResult = false
        for file in selectedAudioFiles {
            print("@@@DEBUG: Transcription begining, file: \(file.fileUrl)")
            if file.isSupportFormat,
                let foundIndex = viewModel.selectedAudioFiles.firstIndex(where: {
                    $0.fileUrl == file.fileUrl
                })
            {
                print("--- file.isSupportFormat: \(file.isSupportFormat), and transcription begining")
                currentProcessingFile = file

                viewModel.selectedAudioFiles[foundIndex].transcriptionState = .transcribing
                viewModel.selectedAudioFiles[foundIndex].fileState = .transcribing
                viewModel.selectedAudioFiles[foundIndex].transcriptionSegments = []
                
                // 启动转写（注意：此方法内部启动任务后会立即返回，不会阻塞到转写完成）

                await whisperService.transcribeFile(at: file)
                print("@@@DEBUG: 这里是转写完了吗？")
                // 等待该文件真正完成：依赖转写引擎进度到达 1.0，并在过程中持续同步最新片段
                while whisperService.transcriptionEngine.transcriptionProgress < 1.0
                    || whisperService.transcriptionEngine.isTranscribing
                {
                    if Task.isCancelled { break }
                    // 关键：转写进行中，实时同步最新片段到当前文件
                    /*
                    if let foundIndex = viewModel.selectedAudioFiles.firstIndex(where: { $0.fileUrl == file.fileUrl }) {
                            viewModel.selectedAudioFiles[foundIndex].transcriptionSegments = whisperService.transcriptionEngine.confirmedSegments
                            print("@@@DEBUG: 同步转写结果: Index: \(fileIndex), file: \(file.fileUrl)")
                    }
                    */
                    // 延时供执行后台进程
                    try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
                }

                // 完成后再做最终一次回填，确保落盘一致
                viewModel.selectedAudioFiles[foundIndex].transcriptionState = .finished
                viewModel.selectedAudioFiles[foundIndex].fileState = .transcribed
                viewModel.selectedAudioFiles[foundIndex].transcriptionSegments =
                    whisperService.transcriptionEngine.confirmedSegments
                viewModel.selectedAudioFiles[foundIndex].transcrDuration =
                    whisperService.transcriptionEngine.duration
                if viewModel.selectedAudioFiles[foundIndex].fileDuration == 0 {
                    viewModel.selectedAudioFiles[foundIndex].fileDuration =
                        whisperService.transcriptionEngine.totalAudioDuration
                }
                isHaveCompletedResult = true
                print("@@@DEBUG: 转写进度更新5: Index: \(foundIndex), segments: \(viewModel.selectedAudioFiles[foundIndex].transcriptionSegments.count), Progress: \(whisperService.transcriptionEngine.transcriptionProgress * 100)%, Duration: \(whisperService.transcriptionEngine.duration)")
            }
        }
        whisperService.resetTranscriptionState()  // 停止转写
        print("!!!!---------------- Hello everyone, transcription is End ----------------!!!!")
        // 所有文件转录完成，页面状态切换为 transcribed
        viewModel.transcribeFileViewState = .transcribed
        isTranscribing = false
        // ... existing code ...
    }

    // 导出转写结果
    func exportTranscription() async {

        @AppStorage("exportPath") var exportPath: String = ""
        @AppStorage("exportFormat") var exportFormat: ExportFormat = ExportFormat.txt

        print("@@@DEBUG: Starting export... Format: \(exportFormat)")

        if let publicDocumentsDirectoryURL = viewModel.publicDocumentsDirectoryURL {

            if exportPath.isEmpty || !FileManager.default.fileExists(atPath: exportPath) {
                exportPath = publicDocumentsDirectoryURL.appendingPathComponent("transee_export").path
            }

            let exportUrl = URL(fileURLWithPath: exportPath)

            print("@@@DEBUG: Exporting to: \(exportUrl.path)")

            for file in viewModel.selectedAudioFiles {
                // 跳过没有转写结果的文件
                if file.transcriptionSegments.isEmpty {
                    print("@@@DEBUG: Skipping \(file.fileBaseName) - No segments found")
                    continue
                }

                // 转换数据格式
                var content: String = ""
                // 根据格式生成内容
                switch exportFormat {
                    case .srt:
                        content = await makeSRT(from: file.transcriptionSegments)
                    case .ass:
                        content = await makeASS(from: file.transcriptionSegments)
                    case .json:
                        content = await makeJSON(from: file.transcriptionSegments) ?? "{}"
                    case .txt:
                        content = await makeText(from: file.transcriptionSegments)
                    default:
                        print("Unsupported format: \(exportFormat), defaulting to txt")
                        content = await makeText(from: file.transcriptionSegments)
                }

                // 构建导出文件名
                let fileNameWithoutExtension = file.fileUrl.deletingPathExtension().lastPathComponent
                let exportFileURL = exportUrl.appendingPathComponent(
                    "\(fileNameWithoutExtension).\(exportFormat.rawValue.lowercased())")
                print("@@@DEBUG: Success Exporting to: \(exportFileURL.path)")
                do {
                    try content.write(to: exportFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("@@@DEBUG: Failed to export \(file.fileBaseName): \(error.localizedDescription)")
                }

                // Add to history
                let historyItem = TranscriptionHistoryItem(
                    originalFileName: file.fileBaseName,
                    originalFilePath: file.fileUrl.path,
                    outputFilePath: exportFileURL.path,
                    timestamp: Date(),
                    modelName: whisperService.getSelectedModel(),
                    language: whisperService.getSelectedLanguage(),
                    duration: file.fileDuration,
                    outputFormat: exportFormat.rawValue.lowercased()
                )
                historyManager.add(historyItem)
            }
            // 可以在这里添加导出完成的提示，例如 Toast
        }
    }

    // 停止转录文件

    func transcriptionStop() {
        // 停止转录文件
        whisperService.resetTranscriptionState()
        
        // 检查当前是否有任何文件包含已转写的片段
        let hasTranscribedContent = viewModel.selectedAudioFiles.contains { !$0.transcriptionSegments.isEmpty }
        
        if hasTranscribedContent {
            // 如果有部分转写结果，进入 transcribed 状态以允许导出
            viewModel.transcribeFileViewState = .transcribed
            for var selectedFile in viewModel.selectedAudioFiles {  
                if !selectedFile.transcriptionSegments.isEmpty {
                    selectedFile.transcriptionState = .finished
                }
                else {
                    selectedFile.transcriptionState = .convertingAudio
                }
            }
        } else {
            // 如果没有任何结果，回到选择文件状态（或者 ready 状态）
            viewModel.transcribeFileViewState = .selectFiles
        }
    }

    // 启动计时方法
    func startTimer() {
        transcribeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }
    // 停止计时方法
    func stopTimer() {
        transcribeTimer.upstream.connect().cancel()
    }
}

struct ExportCompleteView: View {
    @Environment(\.dismiss) var dismiss
    let windowSize: CGSize

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.successGreen)
                Spacer()
            }

            Text("Export Complete")
                .font(.system(size: 24))
                .padding()

            Button(NSLocalizedString("Back to Home", comment: "Back to home button label")) {
                // TODO: - 返回主页面
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .frame(width: windowSize.width, height: windowSize.height)
    }
}

/*
struct TranscribeButton: View {

        @State private var isTranscribing = false

        var body: some View {
                SideBarButton(
                        title: isTranscribing ? "Stop" : "Transcribe",
                        icon:  isTranscribing ? "stop.fill" : "play.fill",
                        minWidth: 64,
                        maxWidth: 122,
                        backgroundColor: isTranscribing ? .red : Color.accentBrandPrimary,
                        isActive: true,
                        isLoading: false,
                        action: {
                                isTranscribing.toggle()
                        }
                )
        }
}
*/

// MARK: - PreviewProvider for Xcode Previews
struct DropZoneView_Previews: PreviewProvider {
    static var previews: some View {
        TranscribeFileView(viewModel: MainViewModel())
    }
}

struct ExportCompleteView_Previews: PreviewProvider {
    static var previews: some View {
        ExportCompleteView(windowSize: CGSize(width: 400, height: 300))
    }
}

/*
struct TranscribeButton_Previews: PreviewProvider {
        static var previews: some View {
                TranscribeButton()
                        .padding(16)
        }
}
*/

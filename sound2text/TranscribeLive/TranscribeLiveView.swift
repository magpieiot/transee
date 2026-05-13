//
//  TranscribeliveView.swift
//  sound2text
//
//  Created by gavanwang on 2025/12/9.  
//

import AVFoundation
import AlertToast
import Foundation
import SwiftUI
@preconcurrency import WhisperKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 辅助视图：麦克风指示器
struct MicrophoneIndicator: View {
    let isRecording: Bool
    var body: some View {
        Image(systemName: isRecording ? "mic.fill" : "mic")
            .font(.largeTitle)
            .foregroundColor(isRecording ? .red : .primary)
            .symbolEffect(
                .variableColor.iterative.reversing, options: .repeating, value: isRecording)  // 仅在 iOS 17+ / macOS 14+ 可用
    }
}

//
struct TranscribeliveView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isRecording: Bool = false
    @State private var isTranscribed: Bool = false
    @State private var isMuted: Bool = false
    @State private var errorMessage: String?
    @State private var selectedModel: String = ""
    @State private var selectedLanguage: String = "zh-CN"  // 默认中文
    @State private var selectedAudioSource: String = ""  // 默认使用系统麦克风
    @State private var audioInputOptions: [String] = []  // 音频输入选项

    @State private var fontSize: CGFloat = 17.0  // 默认字体大小
    @State private var isShowEditResultView: Bool = false
    @State private var isShowAlertDialog: Bool = false
    @State private var isShowMicPermissionAlert: Bool = false
    @AppStorage("resultTextFontSize") private var resultTextFontSize: Double = 14.0
    private let bottomAnchorID = "liveTranscriptBottom"

    @State private var audioInputDeviceManager = AudioInputDeviceManager()
    
    // 暂时注释掉，等 WhisperService 定义好后再启用
    @EnvironmentObject var whisperService: WhisperService
    @EnvironmentObject var historyManager: HistoryManager
    
    var body: some View {
        GeometryReader { geometry in
            VStack {  // 整体布局
                
                // MARK: - 转录文本显示区域
                if isRecording || isTranscribed {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(viewModel.transcribeLiveResult, id: \.self) { segment in
                                let start = formatSmartTime(seconds: Double(segment.start))
                                let end = formatSmartTime(seconds: Double(segment.end))
                                HStack {
                                    Text(start)
                                        .font(
                                            .system(
                                                size: resultTextFontSize, weight: .regular, design: .default
                                            ).italic()
                                        )
                                        .frame(width: 48, alignment: .leading)
                                    Text(end)
                                        .font(
                                            .system(
                                                size: resultTextFontSize, weight: .regular, design: .default
                                            ).italic()
                                        )
                                        .frame(width: 48, alignment: .leading)
                                    Text(segment.text)
                                        .font(
                                            .system(
                                                size: resultTextFontSize, weight: .regular, design: .default
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                        }
                        .onChange(of: whisperService.liveTranscriptionEngine.confirmedSegments) { _, newValue in
                            guard !newValue.isEmpty else { return }

                            let existing = viewModel.transcribeLiveResult
                            var appendedSegments: [TranscriptionSegment] = []

                            if let lastExisting = existing.last,
                               let idx = newValue.lastIndex(where: { $0 == lastExisting })
                            {
                                let nextIndex = newValue.index(after: idx)
                                if nextIndex < newValue.endIndex {
                                    appendedSegments = Array(newValue[nextIndex...])
                                } else {
                                    return
                                }
                            } else {
                                if existing.count > newValue.count {
                                    viewModel.transcribeLiveResult = newValue
                                    DispatchQueue.main.async {
                                        withAnimation {
                                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                                        }
                                    }
                                    return
                                } else {
                                    appendedSegments = Array(newValue.dropFirst(existing.count))
                                }
                            }

                            if !appendedSegments.isEmpty {
                                let existingSet = Set(existing)
                                appendedSegments = appendedSegments.filter { !existingSet.contains($0) }
                            }

                            guard !appendedSegments.isEmpty else { return }

                            viewModel.transcribeLiveResult.append(contentsOf: appendedSegments)
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.1))  // 稍微区分背景
                }

                // MARK: - 实时波形
                if isRecording {
                    ZStack {
                        HStack {
                            LiveWaveformView(
                                samples: whisperService.liveTranscriptionEngine.bufferEnergy,
                                totalDuration: whisperService.liveTranscriptionEngine.bufferSeconds
                            )
                        }
                        .padding(.horizontal)

                        HStack {
                            Spacer()
                            HStack {
                                Text(formatSmartTime(seconds: whisperService.liveTranscriptionEngine.duration))
                                    .foregroundColor(.white)
                                    .font(.title)
                                    .bold()
                                    .monospacedDigit()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            }
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(.infinity)

                            Spacer()
                        }
                    }
                }
                else {
                    Spacer()
                }
                
                // MARK: - 控制按钮
                if isTranscribed {
                    HStack {
                        Spacer()
                        returnButton()
                            .padding(.horizontal, 16)
                        editResultButton()
                            .padding(.horizontal, 16)
                        exportButton()
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                else {
                    recordControlButton()
                }


                if !isRecording && !isTranscribed {
                    Text("Click to start recording and transcribing")
                        .padding()
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                }

                // MARK: - 辅助功能/设置
                /*
                Group {
                    DisclosureGroup("Enhanced Setting") {
                        HStack(alignment: .center, spacing: 12) {
                            // Audio Input
                            VStack(alignment: .leading) {
                                Toggle("Record to File", isOn: $viewModel.isLiveRecordToFile)
                                    .toggleStyle(.switch)  // MacOS风格的开关
                            }

                            Divider()
                            
                            // 静音阈值 (VAD Threshold)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Silence Threshold")
                                    Spacer()
                                    Text(
                                        String(
                                            format: "%.1f", whisperService.settings.silenceThreshold
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                }
                                Slider(
                                    value: $whisperService.settings.silenceThreshold, in: 0.0...1.0, step: 0.1
                                ) {
                                    //Text("静音阈值")
                                } minimumValueLabel: {
                                    Text("0")
                                } maximumValueLabel: {
                                    Text("1")
                                        }
                                Text("Lower values are more sensitive (easier to trigger); higher values are less sensitive. Increase in noisy environments.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                */
                // MARK: - 错误/提示信息
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom)
                } 
            }
            .sheet(isPresented: $isShowEditResultView, onDismiss: {
                isShowEditResultView = false
                print("@@@DEBUG: Dismiss Edit Result View")
            }) {
                TranscribeLiveResultView(
                    viewModel: viewModel,
                    sourcefileUrl: nil,
                    editViewTitle: "Live Mic Result",
                    windowSize: CGSize(width: geometry.size.width - 64, height: geometry.size.height - 64)
                )
            }
            .alert("Confirm Return", isPresented: $isShowAlertDialog) {
                Button("Cancel", role: .cancel) { }
                Button("Return", role: .destructive) {
                    // Confirm
                    isShowAlertDialog = false
                    isRecording = false
                    isTranscribed = false
                    viewModel.transcribeFileViewState = .ready
                    viewModel.transcribeLiveResult.removeAll()
                }
            } message: {
                Text("Live Transcription Result will be lost. Are you sure you want to return?")
            }
            .alert("Microphone Permission Required", isPresented: $isShowMicPermissionAlert) {
                Button("Open System Settings") {
                    openMicrophonePrivacySettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please allow this app to access the microphone in System Settings, then start recording again.")
            }
            .onAppear {
                selectedModel = whisperService.settings.defaultModel
                selectedLanguage = whisperService.settings.selectedLanguage
                audioInputOptions = listAudioInputOptions()
                selectedAudioSource = audioInputOptions.first ?? ""  // 默认使用第一个音频输入选项
            }
            .onAppear(perform: requestAuthorization)  // 视图出现时请求权限
        }
    }

    // 开始/停止录音按钮
    private func recordControlButton() -> some View {

        HStack(alignment: .center) {
            Spacer()
            if isRecording {
                muteButton()
                    .hidden()
            }

            SideBarButton(
                title: isRecording ? "Stop" : "Start",
                icon: isRecording ? "stop.fill" : "play.fill",
                alignment: .center,
                labelColor: .white,
                backgroundColor: isRecording ? Color.crayolaRed : Color("twIndigo600"),
                isActive: true,
                isLoading: false,
                isAvailable: true
            ) {
                if isRecording {
                    isRecording = false
                    if !whisperService.liveTranscriptionEngine.confirmedSegments.isEmpty {
                        isTranscribed = true
                    }
                    stopRecording()
                } else {
                    print("@@@DEBUG: Start Recording ...")
                    isRecording = true
                    startRecording()
                }
            }
            /*
            Button {
                if isRecording {
                    isRecording = false
                    if !whisperService.liveTranscriptionEngine.confirmedSegments.isEmpty {
                        isTranscribed = true
                    }
                    stopRecording()
                } else {
                    isRecording = true
                    startRecording()
                }
            } label: {
                Label(isRecording ? "Stop" : "Start", systemImage: isRecording ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
            }
            .disabled(!(whisperService.modelManager.modelState == .loaded))
            .background(isRecording ? Color.crayolaRed : Color.accentColor)
            .cornerRadius(.infinity)
            */

            if isRecording {
                muteButton()
            }
            Spacer()
        }
        .padding(.bottom, 16)
        .animation(.linear(duration: 1), value: isRecording)
    }

    // 静音按钮
    private func muteButton() -> some View {
        Button {
            // Mute Mic or Audio In
            let isMuted = whisperService.liveTranscriptionEngine.isMuted
            if isMuted {
                whisperService.liveTranscriptionEngine.unmuteMic()
            } else {
                whisperService.liveTranscriptionEngine.muteMic()            
            }
        } label: {

            Label( whisperService.liveTranscriptionEngine.isMuted ? "Muting" : "Mute", systemImage: whisperService.liveTranscriptionEngine.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
        }
        .background(whisperService.liveTranscriptionEngine.isMuted ? Color.crayolaRed : Color.accentColor)
        .cornerRadius(.infinity)
        .animation(.easeInOut(duration: 0.3), value: whisperService.liveTranscriptionEngine.isMuted)
    }

    // 取消
    private func returnButton() -> some View {
        Button {
            isShowAlertDialog = true
        } label: {
            Label("Return", systemImage: "chevron.left")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)

        }
        .background(Color.crayolaRed)
        .cornerRadius(.infinity)
    }

    // 编辑结果按钮
    private func editResultButton() -> some View {
        Button {
            //viewModel.transcribeLiveResult = whisperService.liveTranscriptionEngine.confirmedSegments
            isShowEditResultView = true
        } label: {
            Label("Edit", systemImage: "long.text.page.and.pencil")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)

        }
        .background(Color.successGreen)
        .cornerRadius(.infinity)
    }


    // 导出按钮
    private func exportButton() -> some View {
        Button {
            Task {
                // 导出转录文本
                //await whisperService.exportTranscription()
                await exportLiveTranscription()
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.down")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
        }
        .background(Color.gradientTechButton)
        .cornerRadius(.infinity)
    }

    private func startRecording() {
        viewModel.transcribeLiveResult.removeAll()

        Task { @MainActor in
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            switch status {
                case .authorized:
                    errorMessage = nil
                case .notDetermined:
                    let granted = await PermissionManager.shared.requestMicrophonePermission()
                    guard granted else {
                        isRecording = false
                        errorMessage = "Microphone permission was denied. Please enable it in System Settings."
                        isShowMicPermissionAlert = true
                        return
                    }
                case .denied, .restricted:
                    isRecording = false
                    errorMessage = "Microphone permission was denied. Please enable it in System Settings."
                    isShowMicPermissionAlert = true
                    return
                @unknown default:
                    isRecording = false
                    errorMessage = "Unknown microphone permission status."
                    isShowMicPermissionAlert = true
                    return
            }

            await whisperService.transcribeLiveMic()
        }
    }

    private func stopRecording() {
        Task {
            await whisperService.stopLiveTranscribing()
        }
    }

    private func openMicrophonePrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // 导出转写结果
    func exportLiveTranscription() async {

        @AppStorage("exportPath") var exportPath: String = ""
        @AppStorage("exportFormat") var exportFormat: ExportFormat = ExportFormat.txt

        print("@@@DEBUG: Starting export... Format: \(exportFormat)")

        if let publicDocumentsDirectoryURL = viewModel.publicDocumentsDirectoryURL {

            if exportPath.isEmpty || !FileManager.default.fileExists(atPath: exportPath) {
                exportPath = publicDocumentsDirectoryURL.appendingPathComponent("transee_export").path
            }

            let exportUrl = URL(fileURLWithPath: exportPath)

            print("@@@DEBUG: Exporting to: \(exportUrl.path)")

            // 跳过没有转写结果的文件
            if viewModel.transcribeLiveResult.isEmpty {
                print("@@@DEBUG: Skipping - No segments found")
                return
            }
            
            // 转换数据格式 
            var content: String = ""
            // 根据格式生成内容
            switch exportFormat {
                case .srt:
                    content = await makeSRT(from: viewModel.transcribeLiveResult)
                case .ass:
                    content = await makeASS(from: viewModel.transcribeLiveResult)
                case .json:
                    content = await makeJSON(from: viewModel.transcribeLiveResult) ?? "{}"
                case .txt:
                    content = await makeText(from: viewModel.transcribeLiveResult)
                /*
                default:
                    print("Unsupported format: \(exportFormat), defaulting to TXT")
                    content = await makeText(from: viewModel.transcribeLiveResult)
                    */
            }
            
            // 构建导出文件名
            let fileNameWithoutExtension = "livmic-" + Date().formatted(.iso8601
                                                                        .year()
                                                                        .month()
                                                                        .day()
                                                                        .time(includingFractionalSeconds: false)
                                                                        .dateSeparator(.omitted)
                                                                        .timeSeparator(.omitted)
                                                                        )
            let exportFileURL = exportUrl.appendingPathComponent(
                "\(fileNameWithoutExtension).\(exportFormat.rawValue.lowercased())")
            print("@@@DEBUG: Success Exporting to: \(exportFileURL.path)")
            do {
                try content.write(to: exportFileURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    viewModel.alertToast = AlertToast(
                        displayMode: .alert,
                        type: .complete(.green),
                        title: "Export Completed",
                        subTitle: exportFileURL.lastPathComponent,
                    )
                }
            } catch {
                print("@@@DEBUG: Failed to export Live Transcription: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    viewModel.alertToast = AlertToast(
                        displayMode: .alert,
                        type: .error(.red),
                        title: "Export Failed",
                        subTitle: error.localizedDescription
                    )
                }
            }

            // Add to history
            let historyItem = TranscriptionHistoryItem(
                originalFileName: "Live Mic",
                originalFilePath: exportFileURL.path,
                outputFilePath: exportFileURL.path,
                timestamp: Date(),
                modelName: whisperService.getSelectedModel(),
                language: whisperService.getSelectedLanguage(),
                duration: whisperService.liveTranscriptionEngine.duration,
                outputFormat: exportFormat.rawValue.lowercased()
            )
            historyManager.add(historyItem)
            
            // 可以在这里添加导出完成的提示，例如 Toast 或系统通知
            //showToast(message: "导出完成")
        }
    }

    // MARK: - 麦克风和语音识别权限请求
    private func requestAuthorization() {
        /*
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.errorMessage = nil
                case .denied:
                    self.errorMessage = "语音识别权限被拒绝，请在系统设置中授权。"
                case .restricted:
                    self.errorMessage = "设备不支持语音识别。"
                case .notDetermined:
                    self.errorMessage = "语音识别权限尚未决定。"
                @unknown default:
                    self.errorMessage = "未知语音识别权限状态。"
                }
            }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.errorMessage = "麦克风权限被拒绝，请在系统设置中授权。"
                }
            }
        }
        */
    }
}


// MARK: - 辅助视图：麦克风指示器
#Preview {
    TranscribeliveView(viewModel: MainViewModel())
        .environmentObject(WhisperService())
}

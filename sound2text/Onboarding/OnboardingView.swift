//
//  OnboardingView.swift
//  sound2text
//
//  Created by gavanwang on 2026/3/12.
//

import SwiftUI
import AppKit
@preconcurrency import WhisperKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case modelSelection = 2
    case completed = 3
    
    var title: String {
        switch self {
        case .welcome: return NSLocalizedString("Welcome", comment: "Welcome step title")
        case .permissions: return NSLocalizedString("Permissions", comment: "Permissions step title")
        case .modelSelection: return NSLocalizedString("Model Selection", comment: "Model Selection step title")
        case .completed: return NSLocalizedString("Completed", comment: "Completed step title")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var whisperService: TranscriptionService
    @EnvironmentObject var permissionManager: PermissionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("selectedModel") private var selectedModelStorage: String = ""
    @AppStorage("repoName") private var repoNameStorage: String = "argmaxinc/whisperkit-coreml"

    @State private var cmdQMonitor: Any? = nil
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedModel: String = ""
    @State private var isDownloading = false
    @State private var downloadErrorMessage: String? = nil

    private let recommandModelList = [
        "openai_whisper-small",
        "openai_whisper-medium",
        "openai_whisper-large-v3_turbo_954MB",
        "openai_whisper-large-v3_turbo"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            contentView
            
            footerView
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if cmdQMonitor == nil {
                cmdQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let isCommand = event.modifierFlags.contains(.command)
                    let isQ = event.charactersIgnoringModifiers?.lowercased() == "q"
                    if isCommand && isQ {
                        NSApp.terminate(nil)
                        return nil
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let cmdQMonitor {
                NSEvent.removeMonitor(cmdQMonitor)
                self.cmdQMonitor = nil
            }
        }
        .errorAlert(
            isPresented: Binding(
                get: { downloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { downloadErrorMessage = nil }
                }
            ),
            title: "Failed",
            message: downloadErrorMessage ?? "",
            okTitle: "OK"
        )
    }
    
    private var headerView: some View {
        HStack() {
            Spacer()
            progressIndicator
            Spacer()
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                if step != .completed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                        
                        if step != .modelSelection {
                            Rectangle()
                                .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 40, height: 2)
                        }
                    }
                }
            }
        }
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            switch currentStep {
            case .welcome:
                welcomeContent
            case .permissions:
                permissionsContent
            case .modelSelection:
                modelSelectionContent
            case .completed:
                completedContent
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
    
    private var welcomeContent: some View {
            VStack(spacing: 24) {
                Spacer()
                Image("transee")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                
                VStack(spacing: 12) {
                    Text(NSLocalizedString("Welcome to TranSee", comment: "Welcome to TranSee message"))
                        .font(.system(size: 28, weight: .bold))
                    
                    Text(NSLocalizedString("A powerful speech-to-text tool that supports real-time transcription and audio file conversion", comment: "Description of the app"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                Spacer()
            }
    }
    
    private var permissionsContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            VStack(spacing: 16) {
                Text(NSLocalizedString("Need Your Authorization", comment: "Need authorization title"))
                    .font(.system(size: 24, weight: .bold))
                
                Text(NSLocalizedString("To use the app normally, the following permissions are required:", comment: "Permissions required description"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    PermissionRow(
                        icon: "mic.fill",
                        title: NSLocalizedString("Microphone Permission", comment: "Microphone permission title"),
                        description: NSLocalizedString("For real-time speech transcription and recording", comment: "Microphone permission description"),
                        isGranted: permissionManager.microphoneStatus == .granted,
                        onRequestPermission: {
                            Task {
                                _ = await permissionManager.requestMicrophonePermission()
                            }
                        }
                    )
                    
                    PermissionRow(
                        icon: "folder.badge.gearshape",
                        title: NSLocalizedString("Document Access Permission", comment: "Document access permission title"),
                        description: NSLocalizedString("For accessing audio files for transcription", comment: "Document access permission description"),
                        isGranted: permissionManager.documentsFolderStatus == .granted,
                        onRequestPermission: {
                            Task {
                                _ = await permissionManager.requestDocumentsFolderAccess()
                            }
                        }
                    )
                }
                .padding(.top, 8)
            }
            
            if permissionManager.isRequesting {
                Text(NSLocalizedString("Requesting permission...", comment: "Requesting permission message"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.top, 16)
            }
        }
        .onAppear {
            Task {
                await permissionManager.refreshAllStatuses()
            }
        }
    }
    
    private var modelSelectionContent: some View {
            VStack(spacing: 20) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                
                VStack(spacing: 12) {
                    Text(NSLocalizedString("Download Speech Model", comment: "Download speech model title"))
                        .font(.system(size: 24, weight: .bold))
                    
                    Text(NSLocalizedString("Select a model to start transcription", comment: "Select model instruction"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            
            LazyVStack(spacing: 8) {
                ForEach(recommandModelList, id: \.self) { modelName in
                    // 从预定义模型列表中获取模型信息
                    let modelInfo = self.getModelInfo(for: modelName)
                    let sizeMB = Int(modelInfo?.estimatedDownloadSize ?? 0)
                    let sizeText = sizeMB > 0 ? "\(sizeMB)MB" : "N/A"
                    let description = modelInfo?.description ?? "Speech recognition model"
                    
                    ModelSelectionCard(
                        name: modelName,
                        description: description,
                        size: sizeText,
                        isSelected: selectedModel == modelName,
                        progress: isDownloading && selectedModel == modelName
                            ? Double(whisperService.modelManager.loadingProgressValue)
                            : nil
                    ) {
                        selectedModel = modelName
                    }
                }
            }
            .disabled(isDownloading)
            .padding(.top, 8)
        }
    }
    
    private var completedContent: some View {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                
                VStack(spacing: 12) {
                    Text(NSLocalizedString("Setup Completed!", comment: "Setup completed message"))
                        .font(.system(size: 28, weight: .bold))
                    
                    Text(NSLocalizedString("You can now use Sound2Text for speech-to-text conversion", comment: "Use app for speech to text message"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
    }
    
    private var footerView: some View {
        HStack {
            if currentStep != .welcome && currentStep != .completed {
                Button(NSLocalizedString("Previous", comment: "Previous button label")) {
                    withAnimation {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Spacer()

            if currentStep == .welcome {
                Button(NSLocalizedString("Skip", comment: "Skip button label")) {
                hasCompletedOnboarding = true
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.accentBrandPrimary)
                .padding(.horizontal, 16)
                .disabled(isDownloading)
            }
            
            Button(action: handleNextButton) {
                HStack {
                    Text(nextButtonTitle)
                    if currentStep == .modelSelection && selectedModel.isEmpty {
                        EmptyView()
                    } else if currentStep == .completed {
                        EmptyView()
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(nextButtonBackground)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isNextButtonDisabled)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return NSLocalizedString("Get Started", comment: "Get started button label")
        case .permissions: return NSLocalizedString("Authorize", comment: "Authorize button label")
        case .modelSelection: return NSLocalizedString("Download & Finish", comment: "Download and finish button label")
        case .completed: return NSLocalizedString("Enter App", comment: "Enter app button label")
        }
    }
    
    private var nextButtonBackground: Color {
        if currentStep == .permissions && !isPermissionStepCompleted() {
            return Color.gray
        }
        if currentStep == .modelSelection && selectedModel.isEmpty {
            return Color.gray
        }
        return Color.accentBrandPrimary
    }
    
    private var isNextButtonDisabled: Bool {
        if isDownloading {
            return true
        }
        if currentStep == .permissions && !isPermissionStepCompleted() && !permissionManager.isRequesting {
            return true
        }
        if currentStep == .modelSelection && selectedModel.isEmpty {
            return true
        }
        return false
    }
    
    private func getModelInfo(for modelName: String) -> WhisperModelInfo? {
        predefinedModels.first { $0.name == modelName }
    }
    
    private func isPermissionStepCompleted() -> Bool {
        return permissionManager.microphoneStatus == .granted
            && permissionManager.documentsFolderStatus == .granted
    }
    
    private func handleNextButton() {
        switch currentStep {
        case .welcome:
            Task {
                await permissionManager.refreshAllStatuses()
            }
            withAnimation {
                currentStep = .permissions
            }
            
        case .permissions:
            // 只有当两个权限都被授予时，才进入下一步
            if isPermissionStepCompleted() {
                withAnimation {
                    currentStep = .modelSelection
                }
            } else {
                // 如果权限未全部授予，不执行任何操作，用户需要先授予所有权限
            }
            
        case .modelSelection:
            downloadSelectedModel()
            
        case .completed:
            hasCompletedOnboarding = true
        }
    }
    
    private func downloadSelectedModel() {
        guard !selectedModel.isEmpty else { return }

        downloadErrorMessage = nil
        isDownloading = true

        Task {
            await whisperService.modelManager.downloadModel(
                modelName: selectedModel,
                repo: repoNameStorage
            )

            await MainActor.run {
                isDownloading = false

                if let error = whisperService.modelManager.errorMessage {
                    downloadErrorMessage = error
                    return
                }

                if isModelUsableOnDisk(selectedModel) {
                    selectedModelStorage = selectedModel
                    withAnimation {
                        currentStep = .completed
                    }
                } else {
                    downloadErrorMessage = "Model download did not complete successfully. Please check your network connection and try again."
                }
            }
        }
    }

    private func isModelUsableOnDisk(_ modelName: String) -> Bool {
        guard
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return false
        }

        if !SettingsStore().downloadedModelsArray.keys.contains(modelName) {
            return false
        }

        let modelFolderURL = documentsURL
            .appendingPathComponent(whisperService.modelManager.getModelStoragePath())
            .appendingPathComponent(modelName)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }

        let enumerator = FileManager.default.enumerator(
            at: modelFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var compiledModelCount = 0
        while let item = enumerator?.nextObject() as? URL {
            let ext = item.pathExtension.lowercased()
            if ext == "mlmodelc" || ext == "mlpackage" {
                compiledModelCount += 1
                if compiledModelCount >= 2 {
                    return true
                }
            }
        }

        return false
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequestPermission: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isGranted },
                set: { newValue in
                    // 当用户尝试关闭开关时，只允许开启，不允许关闭
                    if newValue && !isGranted {
                        onRequestPermission()
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ModelSelectionCard: View {
    let name: String
    let description: String
    let size: String
    let isSelected: Bool
    let progress: Double?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(size)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)

                if let progress {
                    CircleProgress(
                        thickness: 4,
                        width: 28,
                        progressTextFontSize: 10,
                        progress: min(max(progress, 0), 1)
                    )
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
}

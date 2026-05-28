//
//  ModelSettingView.swift
//  sound2text
//
//  Created by gavanwang on 8/24/25.
//

import SwiftUI
import WhisperKit

struct ModelSettingView: View {
    @State var isModelDownloading = false
    @State var downloadingModel: String = ""
    @State private var interactingModel: String? // 用于记录当前正在交互（右键菜单弹出）的模型
    @State private var isShowDeleteButton = false // 用于控制删除按钮的显示
    @EnvironmentObject var whisperService: TranscriptionService

    private var downloadedModels: [String] {
        whisperService.modelManager.localModels
    }

    private var recommendModels: [String] {
        whisperService.modelManager.recommendedModels.filter { !downloadedModels.contains($0) }
    }

    private var otherModels: [String] {
        whisperService.modelManager.availableModels.filter { !downloadedModels.contains($0) && !whisperService.modelManager.recommendedModels.contains($0) }
    }

    var body: some View {
        VStack{
            HStack(alignment: .center){
                //ModelSectionHeader(title: "Downloaded")
                // Pick language
                Picker(NSLocalizedString("Language", comment: "Language picker label"), selection: $whisperService.settings.selectedLanguage) {
                    ForEach(whisperService.modelManager.availableLanguages, id: \.self) { language in
                        Text(LanguageWhisperResources.getDisplayString(for: language)).tag(language)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
                Button(action: {
                    isShowDeleteButton.toggle()
                }) {
                    Label(
                        isShowDeleteButton ? 
                            NSLocalizedString("Cancel", comment: "Cancel button label") : 
                            NSLocalizedString("Delete", comment: "Delete button label"), 
                        systemImage: isShowDeleteButton ? "xmark.circle.fill" : "trash.fill"
                    )
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                }
                .foregroundColor(Color.crayolaRed)
                .cornerRadius(.infinity)
                .padding(.horizontal, 16)
            }
            .padding(.leading, 16)
            .padding(.top, 16)

            List {
                if !downloadedModels.isEmpty {
                    
                    
                    //.background(Color.brandButtonBackground)
                    Section(NSLocalizedString("Downloaded", comment: "Downloaded models section header")) {
                        ForEach(downloadedModels, id: \.self) { model in
                            ModelInfomationBar(
                                isModelDownloading: $isModelDownloading,
                                isShowDeleteButton: $isShowDeleteButton,
                                downloadingModel: $downloadingModel,
                                modelName: model,
                                modelManager: whisperService.modelManager,
                                settings: whisperService.settings,
                            )
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                }

                if !recommendModels.isEmpty {
                    //ModelSectionHeader(title: "Recommend")
                    Section(NSLocalizedString("Recommend", comment: "Recommended models section header")) {
                        ForEach(recommendModels, id: \.self) { model in
                            ModelInfomationBar(
                                isModelDownloading: $isModelDownloading,
                                isShowDeleteButton: $isShowDeleteButton,
                                downloadingModel: $downloadingModel,
                                modelName: model,
                                modelManager: whisperService.modelManager,
                                settings: whisperService.settings,
                            )
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                        }
                    }   
                }

                if !otherModels.isEmpty {
                    //ModelSectionHeader(title: "Others")
                    Section(NSLocalizedString("Others", comment: "Other models section header")) {
                        ForEach(otherModels, id: \.self) { model in
                            ModelInfomationBar(
                                isModelDownloading: $isModelDownloading,
                                isShowDeleteButton: $isShowDeleteButton,
                                downloadingModel: $downloadingModel,
                                modelName: model,
                                modelManager: whisperService.modelManager,
                                settings: whisperService.settings,
                            )
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                        }
                    }

                    EmptyView()
                        .padding(.vertical, 16)
                }
            }
            
        }
        .padding( .horizontal, 16)
        .onChange(of: whisperService.settings.selectedLanguage) { oldValue,newValue in
            // 当选择的语言改变时，更新模型列表
            print("@@@DEBUG: selectedLanguage: \(newValue)")
        }
    }
}

struct ModelSectionHeader: View {
    @EnvironmentObject var whisperService: TranscriptionService

    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .padding(.leading, 8)
            Spacer()
        }
    }
}

// 模型信息条
struct ModelInfomationBar: View {
    @Binding var isModelDownloading: Bool
    @Binding var isShowDeleteButton: Bool
    @Binding var downloadingModel: String
    @State private var isSpinning: Bool = false

    var modelName: String
    //@EnvironmentObject var whisperService: TranscriptionService
    // 接收需要的对象
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let modelInfo = predefinedModels.first(where: { $0.name == modelName })
        HStack {
            Image(modelInfo?.trademark ?? "")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .padding(.trailing, 8)
                    //.padding(.leading, 16)

            VStack(alignment: .leading, spacing: 0){
                Text(modelName)
                    .font(.headline)
                    .padding(.bottom, 4)
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString("Accuracy", comment: "Model accuracy label"))
                            .font(.subheadline)
                            .frame(width: 64, alignment: .leading)
                        RatingDotsView(rating: modelInfo?.estimatedAccuracy ?? 0)
                    }
                    .frame(width: 160, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                            .frame(width: 14, alignment: .leading)
                        RatingDotsView(rating: modelInfo?.estimatedSpeed ?? 0)
                    }
                    .frame(width: 100, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.fill")
                            .font(.subheadline)
                            .frame(width: 14, alignment: .leading)
                        Text(modelInfo?.estimatedDownloadSizeDisplay ?? "")
                            .font(.subheadline)
                    }
                    .frame(width: 120, alignment: .leading)

                    Spacer()
                }
            }
            Spacer()
            VStack {
                // 本地模型已经下载
                if modelManager.localModels.contains(modelName) {
                    if modelName == settings.selectedModel {
                        switch modelManager.modelState {
                            case .prewarming, .prewarmed, .loading:
                                HStack{
                                    Spacer()
                                    if modelManager.loadingProgressValue == 0 {
                                        Image(systemName: "circle.dotted")
                                            .font(.title)
                                            .foregroundColor(.gray)
                                            .rotationEffect(.degrees(isSpinning ? 360 : 0))
                                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                                            .onAppear {
                                                isSpinning = true
                                            }
                                            .onDisappear {
                                                isSpinning = false
                                            }
                                    }
                                    else {
                                        CircleProgress(
                                            thickness: 4.0,
                                            width: 24,
                                            foreGradient: Gradient(colors: [.successGreen, .successGreen]),
                                            progress: CGFloat(modelManager.loadingProgressValue)
                                        )
                                    }
                                    Spacer()
                                }
                                .frame(width: 120)
                            default:
                                Button{
                                    //settings.selectedModel = modelName
                                } label: {
                                    Text(NSLocalizedString("Activated", comment: "Actived model button label"))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(width: 92)
                                }
                                //.padding(.horizontal, 8)
                                //.padding(.vertical, 4)
                                .foregroundColor(Color.white.opacity(0.8))
                                .background(Color.successGreen)
                                .cornerRadius(.infinity)
                                //.frame(width: 92)
                        }
                            
                    } else {
                        if isShowDeleteButton {
                            DeleteModelButton(modelName: modelName, modelManager: modelManager, settings: settings)
                        }
                        else {
                            SetActiveModelButton(modelName: modelName, modelManager: modelManager, settings: settings)
                            //    .disabled(!isDefaultButtonAvailable)
                        }
                    }
                } else {
                    // 模型未下载
                    switch modelManager.modelState {
                        case .downloading, .downloaded, .prewarming, .prewarmed, .loading, .loaded:
                            if downloadingModel == modelName {
                                CircleProgress(progress: CGFloat(modelManager.loadingProgressValue))
                                /*
                                ZStack(alignment: .center){
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                    ProgressView(value: whisperService.modelManager.loadingProgressValue, total: 1)
                                        .padding(.horizontal, 16)
                                        .frame(width: 40, height: 40)
                                        .progressViewStyle(.circular)
                                    Text( String(Int(whisperService.modelManager.loadingProgressValue * 100)) )
                                }
                                */
                            } else {
                                DownloadModelButton(
                                    isModelDownloading: $isModelDownloading,
                                    downloadingModel: $downloadingModel,
                                    modelName: modelName, modelManager: modelManager, settings: settings
                                )
                            }
                        case .unloaded, .unloading:
                            DownloadModelButton(
                                isModelDownloading: $isModelDownloading,
                                downloadingModel: $downloadingModel,
                                modelName: modelName, modelManager: modelManager, settings: settings
                            )
                    
                    }
                }
            }
            .padding(.vertical, 8)
            //.padding(.trailing, 16)
            //.frame(width: 120)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((modelName == settings.selectedModel) ? Color.secondary.opacity(0.1) : Color.gray.opacity(0.05))
        )
        //.onHover { isHovering = $0 }
    }
}

struct DeleteModelButton: View {
    var modelName: String
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .center){
            //Spacer()
            Button(role: .destructive) {
                // 弹出确认删除的 Alert
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Confirm Delete Model", comment: "Confirm delete model dialog title")
                alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete the model \"%@\"? This action cannot be undone.", comment: "Confirm delete model dialog message"), modelName)
                alert.alertStyle = .warning
                let deleteButton = alert.addButton(withTitle: "Delete")
                deleteButton.hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    modelManager.deleteModel(modelName)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            //Spacer()
        }
        .padding(.horizontal, 16)
        .frame(width: 72, height: 32)
    }

}

struct SetActiveModelButton: View {
    var modelName: String
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settings: SettingsStore
    
    var body: some View {
        Button {
            settings.selectedModel = modelName
            Task {
                let computeOptions = ModelComputeOptions(
                    audioEncoderCompute: settings.encoderComputeUnits,
                    textDecoderCompute: settings.decoderComputeUnits
                )
                await modelManager.loadModel(named: settings.selectedModel, from: settings.repoName, computeOptions: computeOptions)
            }
        } label: {
            Text(NSLocalizedString("Activate", comment: "Activate model button label"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 92)
        }
        .foregroundColor(Color.white.opacity(0.8))
        .background(Color("twIndigo600"))
        .cornerRadius(.infinity)
    }
}

struct DownloadModelButton: View {
    @Binding var isModelDownloading: Bool
    @Binding var downloadingModel: String
    var modelName: String
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Button(action: {
            // 下载模型
            Task {
                isModelDownloading = true
                downloadingModel = modelName
                await modelManager.downloadModel(
                    modelName: modelName,
                    repo: settings.repoName,
                )
                isModelDownloading = false
                downloadingModel = ""
                modelManager.fetchModels()
            }
        }) {
            Text(NSLocalizedString("Download", comment: "Download model button label"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 92)
        }
        .foregroundColor(Color.accentBrandPrimary)
        .background(Color.accentBrandSecondary)
        .cornerRadius(.infinity)
    }
}

// MARK: - 自定义 macOS 设置样式 GroupBoxStyle
struct MacOSSettingsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) { // spacing 0，因为我们会在标题和内容之间手动添加
            // configuration.label 是 GroupBox 的标题内容 (通常是 Text)
            // configuration.content 是 GroupBox 的内部视图
            
            // 确保标题有合适的 macOS 样式
            configuration.label
                .font(.headline) // 稍微大一点，更明确的标题
                .padding(.bottom, 6) // 在标题和内容之间添加一些垂直间距
                .padding(.horizontal, 4) // 标题的水平内边距
            
            // 内部内容（例如你的设置控件列表）
            configuration.content
                // macOS Native `GroupBox` usually has a light border or just a slight background diff
                .padding(.vertical, 8) // GroupBox 内容的垂直内边距
                .padding(.horizontal) // GroupBox 内容的水平内边距
                .background(Color.gray.opacity(0.1)) // 默认背景通常不需要，或者设置一个微妙的颜色
                .cornerRadius(16) // 边角可以稍微圆润，但通常不明显
                .overlay(
                    // 这是一个可选的边框。macOS 设置通常是扁平的，
                    // 但如果你想添加一个非常细的边框来增强分组感，可以这样做。
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5) // 很细的浅灰色边框
                )
        }
        
    }
}

#Preview {
    ModelSettingView()
        .environmentObject(TranscriptionService())
}


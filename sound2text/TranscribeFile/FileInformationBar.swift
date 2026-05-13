//
//  FileInformationBar.swift
//  sound2text
//
//  Created by gavanwang on 10/9/25.
//
import SwiftUI
import AVFoundation

// 文件信息栏
struct FileInformationBar: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var currentProcessingFile: SelectedAudioFile?
    @Binding var currentClickFile: SelectedAudioFile?
    @Binding var isShowTranscriptionTable: Bool
    var fileData: SelectedAudioFile
    //var onFinished: (Double, Bool) -> Void
    
    //@State private var audioMetadata: AudioMetadata?
    //@State private var fileState: AudioFileState = .idle
    //@State private var duration: Double = 0.0
    //@State private var sampleRate: Double = 0.0
    @State private var progress: Double = 0.0
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var whisperService: WhisperService
    //@Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack{
            HStack(alignment: .center) {
                Image(fileData.fileType.preferredFilenameExtension ?? "unknowType")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(fileData.fileBaseName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if fileData.fileState == .transcribed {
                        //显示转写结果
                        Text(fileData.transcriptionSegments.map { $0.text }.joined(separator: " "))
                            .font(.subheadline)
                            .foregroundColor(.accentBrandPrimary)
                            .lineLimit(1)
                    } else {
                        //显示音频数据
                        Text( formatSampleRate(fileData.sampleRate) )
                            .font(.subheadline)
                            .foregroundColor(.accentBrandPrimary)
                    }
                }
                Spacer()
                
                switch fileData.fileState{
                    case .idle, .paused, .playing, .stopped:
                        Text( formatDuration(fileData.fileDuration) )
                            .font(.headline)
                            .foregroundColor(.accentBrandPrimary)
                    case .transcribing:
                        Text(formatSmartTime(seconds: whisperService.transcriptionEngine.duration, type: .forTable))
                            .font(.headline)
                            .foregroundColor(.accentBrandPrimary)
                    case .transcribed:
                        VStack(alignment: .center) {
                            Spacer()
                            Text(formatSmartTime(seconds: fileData.transcrDuration, type: .forTable))
                                .font(.headline)
                                .foregroundColor(.accentBrandPrimary)
                            Text(formatDuration(fileData.fileDuration))
                                .font(.subheadline)
                                .foregroundColor(.accentBrandPrimary)
                            Spacer()
                        }
                    case .error:
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.accentBrandPrimary)
                    case .waiting:
                        Text("--:--")
                            .font(.headline)
                            .foregroundColor(.accentBrandPrimary)
                }
                
                switch fileData.fileState {
                    case .idle:
                        Button(action: {
                            // 点击按钮的逻辑
                            viewModel.transcribeFileViewState = .playing
                            currentProcessingFile = fileData
                            if let index = viewModel.selectedAudioFiles.firstIndex(where: { $0.fileUrl == currentProcessingFile?.fileUrl }) {
                                viewModel.selectedAudioFiles[index].fileState = .playing
                            }
                            print("Now playing File: \(String(describing: currentProcessingFile?.fileBaseName))")
                            
                        }) {
                            Image(systemName: "play.circle")
                                .foregroundColor(fileData.isPlayable ? .accentTechPrimary : .mediumGrayBackground)
                                .font(.title)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!fileData.isPlayable)
                    case .playing, .paused, .stopped:
                        Button(action: {
                            // 点击按钮的逻辑
                            viewModel.transcribeFileViewState = .ready
                            if let index = viewModel.selectedAudioFiles.firstIndex(where: { $0.fileUrl == currentProcessingFile?.fileUrl }) {
                                viewModel.selectedAudioFiles[index].fileState = .idle
                            }
                            print("Now Stop playing File: \(String(describing: currentProcessingFile?.fileBaseName))")
                            
                        }) {
                            Image(systemName: "stop.circle")
                                .foregroundColor(.crayolaRed)
                                .font(.title)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                    case .transcribed:
                        Button(action: {
                            currentClickFile = fileData
                            print("@@@DEBUG: Now click File: \(String(describing: currentClickFile?.fileBaseName))")
                        }) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.successGreen)
                                .font(.title)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                    case .transcribing:
                        Button(action: {
                            // 点击按钮的逻辑
                            
                            
                        }) {
                            CircleProgress(thickness: 8.0, width: 32, progress: whisperService.transcriptionEngine.transcriptionProgress)
                        }
                        .buttonStyle(.borderless)
                    case .waiting:
                        Button(action: {
                            // 点击按钮的逻辑
                            
                            
                        }) {
                            Image(systemName: "clock")
                                .frame(width: 32, height: 32)
                                .foregroundColor(.babyBlue)
                                .font(.title)
                                
                        }
                        .buttonStyle(.borderless)
                    case .error:
                        Button(action: {
                            // 点击按钮的逻辑: 处理错误状态
                            
                            
                        }) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .font(.title)
                        }
                        .buttonStyle(.borderless)
                }
            }
            
        }
        .background((fileData.fileState == .playing && currentProcessingFile != nil && currentProcessingFile == fileData) ? .blue : .clear)
    }
}
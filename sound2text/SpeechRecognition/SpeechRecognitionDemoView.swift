//
//  SpeechRecognitionDemoView.swift
//  sound2text
//
//  Created by Deepmind Antigravity on 2026/01/30.
//

import SwiftUI
import UniformTypeIdentifiers

struct SpeechRecognitionDemoView: View {
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var showFileImporter = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Speech Recognition Demo")
                .font(.title)
                .bold()
            
            // 状态显示
            HStack {
                Text("State: \(speechManagerState)")
                Spacer()
                if speechManager.isRecording {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                        .scaleEffect(1.2)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: speechManager.isRecording)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // 设备内识别开关
            
            // 语言选择
            HStack {

                Text("Language:")
                Picker("Language", selection: $speechManager.currentLocale) {
                    ForEach(speechManager.supportedLocales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: speechManager.currentLocale) { oldLocale, newLocale in
                    speechManager.setLanguage(locale: newLocale)
                    if speechManager.isSupportsOnDeviceRecognition == true {
                        print("@@@该设备支持离线识别：\(newLocale.identifier)")
                    }
                }
            }
            
            // 文本显示区域
            ScrollView {
                Text(speechManager.transcribedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(height: 300)
            .border(Color.gray.opacity(0.3))
            
            // 进度条 (仅文件识别时)
            if speechManager.progress > 0 && speechManager.progress < 1.0 {
                ProgressView(value: speechManager.progress) {
                    Text("Processing File: \(Int(speechManager.progress * 100))%")
                }
            }
            
            // 操作按钮
            HStack(spacing: 20) {
                // 实时录音按钮
                Button(action: {
                    if speechManager.isRecording {
                        speechManager.stopRecording()
                    } else {
                        do {
                            try speechManager.startRecording()
                        } catch {
                            print("Failed to start recording: \(error)")
                        }
                    }
                }) {
                    VStack {
                        Image(systemName: speechManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(speechManager.isRecording ? .red : .blue)
                        Text(speechManager.isRecording ? "Stop Recording" : "Start Live Record")
                    }
                }
                .disabled(!speechManager.isAuthorized)
                
                // 文件识别按钮
                Button(action: {
                    showFileImporter = true
                }) {
                    VStack {
                        Image(systemName: "doc.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        Text("Transcribe File")
                    }
                }
            }
            
            if !speechManager.isAuthorized {
                Text("Permission to access microphone and speech recognition is denied.")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let error = speechManager.lastError {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .onAppear {
            speechManager.requestAuthorization()
            do {
                try speechManager.setOnDeviceRecognition()
            } catch {
                print("Failed to set on-device recognition: \(error)")
            }
            
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // 必须在访问前请求安全范围访问权限
                guard url.startAccessingSecurityScopedResource() else {
                    print("Access denied")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                speechManager.transcribeFile(url: url)
                
            case .failure(let error):
                print("Failed to pick file: \(error.localizedDescription)")
            }
        }
    }
    
    // 助手属性，将状态转换为字符串
    private var speechManagerState: String {
        switch speechManager.state {
        case .idle: return "Idle"
        case .recording: return "Recording..."
        case .processing: return "Processing File..."
        case .completed: return "Completed"
        case .error(_): return "Error"
        }
    }
}

#Preview {
    SpeechRecognitionDemoView()
}

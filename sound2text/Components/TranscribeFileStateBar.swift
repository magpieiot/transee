import SwiftUI
/*
struct TranscribeFileStateBar: View {
    let fileData: SelectedAudioFile
    @EnvironmentObject var whisperService: TranscriptionService
    @Binding var isTranscribing: Bool
    
    @State private var isSpinning = false
    
    var body: some View {
        HStack(alignment: .center) {
            Image("transcribe")
                .resizable()
                .frame(width: 48, height: 48)
                .padding(.trailing, 8)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning ? Animation.linear(duration: 2).repeatForever(autoreverses: false) : .default,
                    value: isSpinning
                )
                .onAppear {
                    // 视图出现时，如果正在转写，立即启动动画
                    if isTranscribing {
                        isSpinning = true
                    }
                }
                .onChange(of: isTranscribing) { _, newValue in
                    isSpinning = newValue
                }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(whisperService.transcriptionEngine.currentText) //.replacingOccurrences(of: whisperService.settings.initialPrompt, with: ""))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: true, vertical: true)
                                .frame(width: geo.size.width, alignment: .topLeading)
                            
                            Color.clear
                                .frame(height: 1)
                                .id("bottomID")
                        }
                        .frame(width: geo.size.width, alignment: .topLeading)
                    }
                    .onChange(of: whisperService.transcriptionEngine.currentText.trimmingCharacters(in: .whitespacesAndNewlines)) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo("bottomID", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        //.padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .frame(height: 64.0)
    }
}

*/
import SwiftUI
import AlertToast
import WhisperKit
import AppKit
import Combine

struct TranscribeResultView: View {
    @ObservedObject var viewModel: MainViewModel
    @State var sourcefileUrl: URL
    var windowSize: CGSize
    @State private var isShowSrtFormat: Bool = false
    @State private var isAlreadyEdited: Bool = false
    @State private var isPlayorPause = false
    @State private var isPlaying = false
    @State private var isSpinning = false
    @State private var isExitConfirmationPresented = false
    @State private var isFormatSubTitleReady: Bool = false
    @State private var isShowToast: Bool = false
    @State private var isCopySuccess: Bool = false
    @State private var escMonitor: Any? = nil
    @State private var currentPlayingIndex: Int? = nil
    @State private var subString: String = ""
    
    @State private var fileIndex: Int = 0
    @State private var showTextFormat: String = "Table"
    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var dataVersion: Int = 0
    @State private var cachedResults: [String: (version: Int, content: String)] = [:]
    
    @FocusState private var focusedRowID: UUID?
    @AppStorage("resultTextFontSize") private var resultTextFontSize: Double = 14.0
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    
    private var currentSegments: [TranscriptionSegment] {
        guard viewModel.selectedAudioFiles.indices.contains(fileIndex) else { return [] }
        return viewModel.selectedAudioFiles[fileIndex].transcriptionSegments
    }
    
    // 提供默认示例数据，初始化时可传入自定义数据
    
    // 频繁调用通常是因为 SwiftUI 的 View diff 系统认为需要重建该 View。
    // 常见原因：
    // 1. viewModel 或 sourcefileUrl 的引用在父级每次刷新时都是新的实例（即使内容没变）。
    // 2. 父级用到了 id(_:) 或 List/ForEach 的 id 不稳定，导致子 View 被销毁重建。
    // 3. 父级依赖的 @State/@ObservedObject 属性频繁发布变化，触发 body 重新求值。
    // 解决思路：
    // - 确保 MainViewModel 是引用类型（class）且在父级只创建一次，用 @StateObject 持有。
    // - 确保传入的 sourcefileUrl 是同一个 URL 实例，不要每次生成新 URL。
    // - 在父级使用 .equatable() 或自定义 == 让 SwiftUI 知道 View 实际未变。
    /*
    init(viewModel: MainViewModel, sourcefileUrl: URL, windowSize: CGSize = .zero) {
        self.viewModel = viewModel
        self.windowSize = windowSize
        self.sourcefileUrl = sourcefileUrl
        //print("@@@DEBUG: sourcefileUrl = \(sourcefileUrl)")
    }
    */
    
    var body: some View {
        VStack(alignment: .leading) {
            // 定制标题栏
            HStack{
                MacOSTrafficLightButton(type: .close){
                    if isPlaying {
                        audioPlayer.stop()
                    }
                    dismiss()
                }
                .padding(.vertical, 24)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                
                Text(sourcefileUrl.pathComponents.last ?? "")
                    .font(.headline)
                    .fontWeight(.medium)
                    .padding(.trailing, 16)

                if isAlreadyEdited {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                }

                Spacer()
                /*
                // 编辑退回
                Button(action: {
                    //
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        //.background(Color.primary.opacity(0))
                }
                .buttonStyle(.borderless)
                */

                // 复制到剪贴板
                SideBarButton(
                    title: "Copy Text",
                    icon: "doc.on.doc.fill",
                    minWidth: 120,
                    maxWidth: 120,
                    height: 32.0,
                    action: {
                        Task {
                            subString = await makeText(from: currentSegments, onProgress: { @Sendable _, progress in
                                print("@@@DEBUG: Make Text progress: \(progress*100.0)%")
                            })   
                            print("@@@DEBUG: Make Text progress Finish")

                            let result =  copyToPasteboard(text: subString)
                            if result {
                                // 显示成功提示
                                isCopySuccess = true
                                isShowToast = true
                            } else {
                                // 显示失败提示
                                isCopySuccess = false
                                isShowToast = true
                            }
                        } 
                    }
                )
                .padding(.trailing, 16.0)
                
                // 保存按钮
                /*
                Button(action: {
                    isAlreadyEdited = false
                }) {
                    Image(systemName: "arrow.up.document.fill")
                        .font(.system(size: 16))
                        .foregroundColor( isAlreadyEdited ? .primary : .gray.opacity(0.5) )
                        //.background(Color.primary.opacity(0))
                }
                .buttonStyle(.borderless)
                .disabled(!isAlreadyEdited)
                */
            
                /*
                Picker("", selection: $showTextFormat) {
                    Text("Table").tag("Table")
                    Text("SRT").tag("SRT")
                    Text("ASS").tag("ASS")
                    Text("JSON").tag("JSON")
                    Text("Text").tag("TXT")
                }
                .pickerStyle(.segmented) // 分段选择器
                .padding(.trailing, 16)
                */
                /*
                Toggle("显示SRT格式", isOn: $isShowSrtFormat)
                    .toggleStyle(.switch)
                    .padding(.trailing, 16)
                    */
            }
            .background(Color.primary.opacity(0.1))

            HStack(alignment: .top) {
                
                switch showTextFormat {
                    case "SRT", "ASS", "JSON", "TXT":
                        if isFormatSubTitleReady {
                            showFormatTextView(content: subString)
                        } else {
                            Text("请先生成\(showTextFormat)格式字幕")
                        }
                    default:
                        List {
                            ForEach(currentSegments.indices, id: \.self) { index in
                                let segment = currentSegments[index]
                                let start = formatSmartTime(seconds: Double(segment.start))
                                let end = formatSmartTime(seconds: Double(segment.end))
                                let textBinding = textBinding(for: index)
                                let rowHeightBinding = heightBinding(for: index)
                                let rowIsPlaying = isRowPlaying(index)
                                HStack {
                                    Text(String(index + 1))
                                        .font(.system(size: resultTextFontSize, weight: .heavy, design: .default))
                                        .frame(width: 32, alignment: .leading)
                                    Text(start)
                                        .font(.system(size: resultTextFontSize, weight: .regular, design: .default).italic())
                                        .frame(width: 48, alignment: .leading)
                                    Text(end)
                                        .font(.system(size: resultTextFontSize, weight: .regular, design: .default).italic())
                                        .frame(width: 48, alignment: .leading)
                                    GeometryReader { geo in
                                        IMETextEditor(text: textBinding, calculatedHeight: rowHeightBinding, rowSN: index, font: .systemFont(ofSize: resultTextFontSize), measureWidth: geo.size.width, onEdited: { 
                                            isAlreadyEdited = true
                                            dataVersion += 1
                                        })
                                    }
                                    .frame(height: rowHeights[index] ?? 16.0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Button(action: {
                                        let isCurrent = (currentPlayingIndex == index)
                                        let willPlay = !isCurrent
                                        if willPlay {
                                            currentPlayingIndex = index
                                            isPlaying = true
                                            isPlayorPause = true
                                            audioPlayer.seek(to: Double(segment.start))
                                            audioPlayer.play()
                                        } else {
                                            currentPlayingIndex = nil
                                            isPlaying = false
                                            isPlayorPause = false
                                            audioPlayer.pause()
                                        }
                                    }) {
                                        Image(systemName: rowIsPlaying ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.system(size: resultTextFontSize))
                                            .foregroundColor(rowIsPlaying ? .red : .green)
                                    }
                                    .frame(width: 24)
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                }
            }
            
            Spacer()
            
            if isPlaying {
                audioPlayerBar(playingUrl: sourcefileUrl)
            }
        }
        //.navigationTitle(fileUrl.lastPathComponent)
        .frame(minWidth: windowSize.width, minHeight: windowSize.height)
        .toast(isPresenting: $isShowToast, duration: 3.0) {
            if isCopySuccess {
                AlertToast(displayMode: .hud, type: .complete(Color.green), title: "Copy Success")
            } else {
                AlertToast(displayMode: .hud, type: .error(Color.red), title: "Copy Failed")
            }
        }
        .onAppear {
            print("@@@DEBUG: TranscribeResultView onAppear. \(sourcefileUrl.path)")
            audioPlayer.loadAudio(from: sourcefileUrl)
            fileIndex = viewModel.selectedAudioFiles.firstIndex(where: { $0.fileUrl == sourcefileUrl }) ?? 0
            //textViewHeight = Array(repeating: 16.0, count: rows.count)

            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    isExitConfirmationPresented = true
                    return nil
                }
                return event
            }
        }
        .onReceive(audioPlayer.$currentTime.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)) { time in
            updatePlayingRow(for: time)
        }
        .onChange(of: isPlayorPause) { _, newValue in
            if !newValue {
                currentPlayingIndex = nil
            }
        }
        .alert("Are you sure you want to exit?", isPresented: $isExitConfirmationPresented) {
            Button("Exit", role: .destructive) {
                if isPlaying { audioPlayer.stop() }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
        .onDisappear {
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
        }
    }

    private func showFormatTextView(content: String) -> some View {
        ScrollView {
            Text(content)
                .lineLimit(nil)
                .font(.system(size: resultTextFontSize))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
        }
    }

    // 音频播放条
    func audioPlayerBar(playingUrl: URL) -> some View {
        HStack(alignment: .center){
            Image("vinylrecord3")
                .resizable()
                .frame(width: 48, height: 48)
                .rotationEffect(isSpinning ? .degrees(360) : .degrees(0))
                .animation(
                    isSpinning ? Animation.linear(duration: 2).repeatForever(autoreverses: false) : .default,
                    value: isSpinning
                )

            Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration) {
                Text("")
            } minimumValueLabel: {
                Text(audioPlayer.currentTimeString)
            } maximumValueLabel: {
                Text(audioPlayer.durationString)
            }

            // 播放按钮
            Button(action: {
                isPlayorPause.toggle()
                if isPlayorPause {
                    audioPlayer.play()
                    isPlaying = true
                } else {
                    audioPlayer.pause()
                    isPlaying = false
                    currentPlayingIndex = nil
                }
            }) {
                Image(systemName: isPlayorPause ? "pause.circle" : "play.circle")
                    .foregroundColor(.orange)
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
        .onAppear { isSpinning = isPlayorPause }
        .onChange(of: isPlayorPause) { oldValue, newValue in
            isSpinning = newValue
        }
        .onDisappear { isSpinning = false }
    }
        

    // 为表格中的行获取双向绑定，以便在 TextField 中编辑
    private func textBinding(for index: Int) -> Binding<String> {
        Binding<String>(
            get: {
                guard viewModel.selectedAudioFiles.indices.contains(fileIndex),
                      viewModel.selectedAudioFiles[fileIndex].transcriptionSegments.indices.contains(index)
                else { return "" }
                return viewModel.selectedAudioFiles[fileIndex].transcriptionSegments[index].text
            },
            set: { newValue in
                guard viewModel.selectedAudioFiles.indices.contains(fileIndex),
                      viewModel.selectedAudioFiles[fileIndex].transcriptionSegments.indices.contains(index)
                else { return }
                let segment = viewModel.selectedAudioFiles[fileIndex].transcriptionSegments[index]
                let updated = TranscriptionSegment(
                    id: segment.id,
                    seek: segment.seek,
                    start: segment.start,
                    end: segment.end,
                    text: newValue,
                    tokens: segment.tokens,
                    temperature: segment.temperature,
                    avgLogprob: segment.avgLogprob,
                    compressionRatio: segment.compressionRatio,
                    noSpeechProb: segment.noSpeechProb,
                    words: segment.words
                )
                viewModel.selectedAudioFiles[fileIndex].transcriptionSegments[index] = updated
            }
        )
    }

    private func heightBinding(for index: Int) -> Binding<CGFloat> {
        Binding<CGFloat>(
            get: { rowHeights[index] ?? 24 },
            set: { rowHeights[index] = $0 }
        )
    }

    private func isRowPlaying(_ index: Int) -> Bool {
        currentPlayingIndex == index && isPlayorPause
    }

    private func updatePlayingRow(for time: Double) {
        guard isPlayorPause else {
            currentPlayingIndex = nil
            return
        }
        currentPlayingIndex = currentSegments.firstIndex(where: { time >= Double($0.start) && time < Double($0.end) })
    }

    // IME 友好的多行文本编辑器，支持多行自适应与滚动
    /*
    struct IMETextEditor: NSViewRepresentable {
        @Binding var text: String
        var fontSize: Double

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder

            let tv = NSTextView()
            tv.isEditable = true
            tv.isRichText = false
            tv.allowsUndo = true
            tv.drawsBackground = false
            tv.font = NSFont.systemFont(ofSize: CGFloat(fontSize))
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.textContainerInset = .zero
            if let container = tv.textContainer {
                container.widthTracksTextView = true
                let initialWidth = max(10, scrollView.bounds.width)
                container.containerSize = NSSize(width: initialWidth, height: .greatestFiniteMagnitude)
            }

            scrollView.documentView = tv
            NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.textDidChange(_:)), name: NSText.didChangeNotification, object: tv)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let tv = scrollView.documentView as? NSTextView else { return }
            tv.font = NSFont.systemFont(ofSize: CGFloat(fontSize))
            if tv.hasMarkedText() { return }
            if tv.string != text { tv.string = text }
            if let container = tv.textContainer {
                let widthCandidate = max(10, scrollView.bounds.width)
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: widthCandidate, height: .greatestFiniteMagnitude)
            }
        }



        class Coordinator: NSObject {
            var parent: IMETextEditor
            init(_ parent: IMETextEditor) { self.parent = parent }
            @objc func textDidChange(_ notification: Notification) {
                guard let tv = notification.object as? NSTextView else { return }
                if !tv.hasMarkedText() { parent.text = tv.string }
            }
        }
    }
    */

    // 自动自适应高度的 SwiftUI 包装器
    /*
    struct AutoSizingIMETextEditor: View {
        @Binding var text: String
        var fontSize: Double
        var body: some View {
            GeometryReader { geo in
                let width = max(10, geo.size.width)
                let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
                let attributed = NSAttributedString(string: text, attributes: [.font: font])
                let rect = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
                let height = max(24, ceil(rect.height) + 6)
                IMETextEditor(text: $text, fontSize: fontSize)
                    .frame(height: height)
            }
        }
    }
    */
}

#Preview {
    TranscribeResultView(
        viewModel: MainViewModel(),
        sourcefileUrl: URL(fileURLWithPath: ""),
        windowSize: .init(width: 800, height: 600),
    )
}

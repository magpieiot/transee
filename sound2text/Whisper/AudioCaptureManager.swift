//
//  AudioCaptureManager.swift
//  sound2text
//

import AVFoundation
import CoreAudio
import Combine

/// 独立的录音管理器，负责从麦克风捕获音频数据并转换为统一的 [Float] (16kHz PCM Float32) 格式。
/// 这样 WhisperKitLiveEngine 就不再直接依赖 WhisperKit 的 AudioProcessor。
public class AudioCaptureManager: ObservableObject, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    
    @Published public var isRecording = false
    
    // 目标采样率： Whisper 和大多数语音模型（如 Speech-Swift 推荐）均使用 16kHz
    private let targetSampleRate: Double = 16000.0
    private var converter: AVAudioConverter?
    
    public init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(mixerNode)
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // 目标格式：16kHz, 单声道, 32-bit Float PCM
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSampleRate,
                                               channels: 1,
                                               interleaved: false) else {
            print("Failed to create target AVAudioFormat")
            return
        }
        
        audioEngine.connect(inputNode, to: mixerNode, format: inputFormat)
        
        // 创建转换器
        self.converter = AVAudioConverter(from: mixerNode.outputFormat(forBus: 0), to: targetFormat)
    }
    
    /// 开始录音
    /// - Parameter audioDataHandler: 回调函数，返回转换后的 [Float] 数组
    public func startRecording(audioDataHandler: @escaping ([Float]) -> Void) throws {
        guard !audioEngine.isRunning else { return }
        
        let inputNode = audioEngine.inputNode
        let mixerFormat = mixerNode.outputFormat(forBus: 0)
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSampleRate,
                                               channels: 1,
                                               interleaved: false) else {
            throw NSError(domain: "AudioCaptureManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid target format"])
        }
        
        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: mixerFormat) { [weak self] (buffer, time) in
            guard let self = self, let converter = self.converter else { return }
            
            // 计算需要的容量
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (self.targetSampleRate / mixerFormat.sampleRate))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            
            var error: NSError? = nil
            var allDataConverted = false
            
            converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if allDataConverted {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allDataConverted = true
                outStatus.pointee = .haveData
                return buffer
            }
            
            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let frameLength = Int(convertedBuffer.frameLength)
                let floatArray = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
                
                // 将转换好的 Float 数组传出
                audioDataHandler(floatArray)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    /// 停止录音
    public func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            mixerNode.removeTap(onBus: 0)
            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
    }
}

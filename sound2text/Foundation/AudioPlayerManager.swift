import AVFoundation
import Combine
import Foundation

@MainActor
class AudioPlayerManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var shouldPlayAudioOnly = false

    // MARK: - Initialization
    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        let player = player
        let timeObserver = timeObserver
        cancellables.removeAll()

        DispatchQueue.main.async {
            if let timeObserver {
                player?.removeTimeObserver(timeObserver)
            }
            player?.pause()
        }
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        #if os(iOS)
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
                try audioSession.setActive(true)
            } catch {
                self.error = error
                print("Failed to setup audio session: \(error)")
            }
        #elseif os(macOS)
            // macOS 不需要 AVAudioSession 配置
            // 音频会话由系统自动管理
        #endif
    }

    // MARK: - Public Methods

    /// 加载音频URL（支持本地文件和HLS流媒体）
    func loadAudio(from url: URL) {
        cleanup()
        shouldPlayAudioOnly = false
        isLoading = true
        error = nil

        // 创建AVPlayerItem
        playerItem = AVPlayerItem(url: url)

        // 设置播放器
        player = AVPlayer(playerItem: playerItem)

        // 添加观察者
        setupObservers()

        // 等待播放器准备就绪
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    self?.handlePlayerItemStatusChange(status)
                }
            }
            .store(in: &cancellables)
    }

    /// 加载视频文件中的音频（仅仅播放音频）
    /// - Parameter url: 视频或音频文件的 URL
    func loadAudioOnly(from url: URL) {
        cleanup()
        shouldPlayAudioOnly = true
        isLoading = true
        error = nil

        // 创建AVPlayerItem
        playerItem = AVPlayerItem(url: url)

        // 设置播放器
        player = AVPlayer(playerItem: playerItem)

        // 添加观察者
        setupObservers()

        // 等待播放器准备就绪
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    self?.handlePlayerItemStatusChange(status)
                }
            }
            .store(in: &cancellables)
    }

    /// 播放音频
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
    }

    /// 暂停播放
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
    }

    /// 停止播放
    func stop() {
        guard let player = player else { return }
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }

    /// 跳转到指定时间
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentTime = time
            }
        }
    }

    /// 快进（默认15秒）
    func fastForward(seconds: TimeInterval = 15) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    /// 快退（默认15秒）
    func rewind(seconds: TimeInterval = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    /// 设置播放速度
    func setPlaybackRate(_ rate: Float) {
        guard let player = player else { return }
        player.rate = rate
        playbackRate = rate

        // 如果设置速度时播放器正在播放，需要重新开始播放
        if isPlaying {
            player.play()
        }
    }

    /// 设置音量
    func setVolume(_ volume: Float) {
        guard let player = player else { return }
        let clampedVolume = max(0, min(1, volume))
        player.volume = clampedVolume
        self.volume = clampedVolume
    }

    /// 获取当前播放进度（0-1）
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// 设置播放进度（0-1）
    func setProgress(_ progress: Double) {
        let clampedProgress = max(0, min(1, progress))
        let targetTime = duration * clampedProgress
        seek(to: targetTime)
    }

    // MARK: - Private Methods

    private func setupObservers() {
        guard let player = player else { return }

        // 添加时间观察者
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.1, preferredTimescale: timeScale)

        timeObserver = player.addPeriodicTimeObserver(forInterval: time, queue: .main) {
            [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }

        // 观察播放结束
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePlaybackFinished()
                }
            }
            .store(in: &cancellables)

        // 观察播放失败
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .sink { [weak self] notification in
                DispatchQueue.main.async {
                    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    {
                        self?.error = error
                    }
                }
            }
            .store(in: &cancellables)

        // 观察播放器状态变化（适用于所有平台）
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .playing:
                        self?.isPlaying = true
                    case .paused:
                        self?.isPlaying = false
                    case .waitingToPlayAtSpecifiedRate:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func handlePlayerItemStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isLoading = false
            if let duration = playerItem?.duration, duration.isValid {
                self.duration = duration.seconds
            }

            // 如果是仅播放音频模式，禁用视频轨道
            if shouldPlayAudioOnly, let playerItem = playerItem {
                playerItem.tracks.forEach { track in
                    if track.assetTrack?.mediaType == .video {
                        track.isEnabled = false
                    }
                }
            }
        case .failed:
            isLoading = false
            if let error = playerItem?.error {
                self.error = error
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = 0
        player?.seek(to: .zero)
    }

    private func cleanup() {
        // 移除时间观察者
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            //self.activityTimeObserver = nil  // Fixed a potential typo in original if it existed, but using what's there
            self.timeObserver = nil
        }

        // 取消所有订阅
        cancellables.removeAll()

        // 清理播放器
        player?.pause()
        player = nil
        playerItem = nil

        // 重置状态
        isPlaying = false
        currentTime = 0
        duration = 0
        isLoading = false
        error = nil
    }

    /// 播放视频文件中的音频（仅仅播放音频）
    /// - Parameter url: 视频或音频文件的 URL
    /// - Returns: 一个配置好的 AVPlayer 实例
    static func playAudioOnly(from url: URL) -> AVPlayer {
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.play()
        return player
    }
}

// MARK: - Convenience Extensions
extension AudioPlayerManager {
    /// 格式化时间显示
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 当前时间的格式化字符串
    var currentTimeString: String {
        formatTime(currentTime)
    }

    /// 总时长的格式化字符串
    var durationString: String {
        formatTime(duration)
    }

    /// 剩余时间的格式化字符串
    var remainingTimeString: String {
        formatTime(duration - currentTime)
    }

    /// 检查是否支持当前音频格式
    static func isSupportedAudioFormat(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        if #available(macOS 13.0, *) {
            var isPlayable = false
            // 异步加载 isPlayable 属性
            let playableStatus = try? await asset.load(.isPlayable)
            isPlayable = playableStatus ?? false
            return isPlayable
        } else {
            // 在旧版本系统上使用 isPlayable
            return asset.isPlayable
        }
    }
}

// MARK: - Error Types
enum AudioPlayerError: Error, LocalizedError {
    case invalidURL
    case loadFailed
    case playbackFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的音频URL"
        case .loadFailed:
            return "音频加载失败"
        case .playbackFailed:
            return "音频播放失败"
        case .unsupportedFormat:
            return "不支持的音频格式"
        }
    }
}

//
//  PermissionManager.swift
//  TranSee
//
//  Created by gavanwang on 2026/3/12.
//

import Foundation
import AVFoundation
import Speech
import UserNotifications
import AppKit

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var notificationStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var speechRecognitionStatus: PermissionStatus = .notDetermined
    @Published var documentsFolderStatus: PermissionStatus = .notDetermined
    @Published var documentsFolderURL: URL?
    @Published var isRequesting = false
    
    enum PermissionStatus: String {
        case notDetermined = "未决定"
        case granted = "已授权"
        case denied = "已拒绝"
    }

    private let documentsBookmarkKey = "publicDocumentsBookmark"
    private var documentsFolderIsAccessing = false

    func refreshAllStatuses() async {
        await checkNotificationStatus()
        checkMicrophoneStatus()
        checkSpeechRecognitionStatus()
        await checkDocumentsFolderStatus()
    }
    
    /// 请求通知权限
    func requestNotificationPermission() async {
        isRequesting = true
        
        let center = UNUserNotificationCenter.current()
        let status = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        
        self.notificationStatus = status ? .granted : .denied
        self.isRequesting = false
    }
    
    /// 检查通知权限状态
    func checkNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        
        switch status {
        case .authorized, .ephemeral, .provisional:
            self.notificationStatus = .granted
        case .denied:
            self.notificationStatus = .denied
        case .notDetermined:
            self.notificationStatus = .notDetermined
        @unknown default:
            self.notificationStatus = .notDetermined
        }
    }
    
    func checkMicrophoneStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    func requestMicrophonePermission() async -> Bool {
        isRequesting = true

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        microphoneStatus = granted ? .granted : .denied
        isRequesting = false
        return granted
    }

    func checkSpeechRecognitionStatus() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionStatus = .granted
        case .denied, .restricted:
            speechRecognitionStatus = .denied
        case .notDetermined:
            speechRecognitionStatus = .notDetermined
        @unknown default:
            speechRecognitionStatus = .notDetermined
        }
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        isRequesting = true

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }

        switch status {
        case .authorized:
            speechRecognitionStatus = .granted
            isRequesting = false
            return true
        case .denied, .restricted, .notDetermined:
            speechRecognitionStatus = .denied
            isRequesting = false
            return false
        @unknown default:
            speechRecognitionStatus = .notDetermined
            isRequesting = false
            return false
        }
    }

    func checkDocumentsFolderStatus() async {
        let url = await loadDocumentsFolderFromBookmark()
        documentsFolderStatus = url == nil ? .notDetermined : .granted
    }

    func ensureDocumentsFolderAccess() async -> URL? {
        if let url = await loadDocumentsFolderFromBookmark() {
            documentsFolderStatus = .granted
            return url
        }

        if let url = await requestDocumentsFolderAccess() {
            documentsFolderStatus = .granted
            return url
        }

        documentsFolderStatus = .denied
        return nil
    }

    func restoreDocumentsFolderAccess() async -> URL? {
        let url = await loadDocumentsFolderFromBookmark()
        documentsFolderStatus = url == nil ? .notDetermined : .granted
        return url
    }

    func requestDocumentsFolderAccess() async -> URL? {
        isRequesting = true

        let selectedURL: URL? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.prompt = "Select Documents Folder"
                panel.message = "Please select your Documents folder where the application can access files."
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                panel.setContentSize(NSSize(width: 720, height: 520))
                panel.minSize = NSSize(width: 720, height: 520)
                panel.center()

                let presentingWindow = NSApp.mainWindow ?? NSApp.keyWindow
                if let presentingWindow {
                    panel.beginSheetModal(for: presentingWindow) { response in
                        continuation.resume(returning: response == .OK ? panel.url : nil)
                    }
                } else {
                    panel.begin { response in
                        continuation.resume(returning: response == .OK ? panel.url : nil)
                    }
                }
            }
        }

        guard let selectedURL else {
            isRequesting = false
            documentsFolderStatus = .denied
            return nil
        }

        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: documentsBookmarkKey)
        } catch {
            isRequesting = false
            documentsFolderStatus = .denied
            return nil
        }

        let url = await loadDocumentsFolderFromBookmark()
        isRequesting = false

        if url == nil {
            documentsFolderStatus = .denied
        } else {
            documentsFolderStatus = .granted
        }

        return url
    }

    func stopAccessingDocumentsFolderIfNeeded() {
        guard documentsFolderIsAccessing else { return }
        documentsFolderURL?.stopAccessingSecurityScopedResource()
        documentsFolderIsAccessing = false
    }

    private func loadDocumentsFolderFromBookmark() async -> URL? {
        if documentsFolderIsAccessing, let documentsFolderURL {
            return documentsFolderURL
        }

        guard let bookmarkData = UserDefaults.standard.data(forKey: documentsBookmarkKey) else {
            documentsFolderURL = nil
            documentsFolderIsAccessing = false
            return nil
        }

        do {
            var isStale = false
            let bookmarkedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                UserDefaults.standard.removeObject(forKey: documentsBookmarkKey)
                documentsFolderURL = nil
                documentsFolderIsAccessing = false
                return nil
            }

            let didStartAccessing = bookmarkedURL.startAccessingSecurityScopedResource()
            if didStartAccessing {
                documentsFolderIsAccessing = true
                documentsFolderURL = bookmarkedURL
                return bookmarkedURL
            }

            documentsFolderURL = nil
            documentsFolderIsAccessing = false
            return nil
        } catch {
            UserDefaults.standard.removeObject(forKey: documentsBookmarkKey)
            documentsFolderURL = nil
            documentsFolderIsAccessing = false
            return nil
        }
    }
    
    /// 打开系统偏好设置（当权限被拒绝时）
    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }
}

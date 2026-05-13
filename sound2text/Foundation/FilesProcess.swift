//
//  fileoperation.swift
//  sound2text
//
//  Created by gavanwang on 8/20/25.
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 定义 M4A 类型作为 UTType
/*
extension UTType {
        static var m4aAudio: UTType {
                UTType(filenameExtension: "m4a")! // ! 表示强制解包，因为这里通常会成功
        }
}
*/

// MARK: - 错误类型定义
// 文件系统错误类型定义
enum FileSystemError: Error, LocalizedError {
    case invalidPath(String)
    case directoryEnumerationFailed(String, Error)
    case fileAccessDenied(String, Error)
    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid path provided: \(path)"
        case .directoryEnumerationFailed(let path, let error):
            return "Failed to enumerate contents of directory '\(path)': \(error.localizedDescription)"
        case .fileAccessDenied(let path, let error):
            return "Access denied for file/directory '\(path)': \(error.localizedDescription)"
        }
    }
}

// MARK: - 文件选择错误类型定义
enum FileSelectionError: LocalizedError {
    case noActiveWindow
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .noActiveWindow:
            return "未找到活动窗口"
        case .userCancelled:
            return "用户取消了文件选择"
        }
    }
}

// MARK: - String Extension for isHidden (macOS specific)
extension URL {
    /// 检查文件或目录是否是隐藏的。
    /// 在 macOS 上，以点开头的文件或目录是隐藏的，但也可以通过文件属性设置隐藏。
    var isHidden: Bool {
        if self.lastPathComponent.hasPrefix(".") {
            return true
        }
        // 尝试获取文件隐藏属性
        if let values = try? self.resourceValues(forKeys: [.isHiddenKey]),
            let isHidden = values.isHidden
        {
            return isHidden
        }
        return false
    }
}

struct FileInfo: Identifiable {
    let id = UUID()
    let path: String
    let size: Int64
}

class FileCounter: ObservableObject {
    @Published var fileCount: Int = 0
    @Published var totalSize: Int64 = 0
    @Published var fileInfos: [FileInfo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    func countFiles(atPath path: String) {
        isLoading = true
        errorMessage = nil
        fileCount = 0
        totalSize = 0
        fileInfos = []
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var count = 0
            var size: Int64 = 0
            var infos: [FileInfo] = []
            
            let enumerator = fileManager.enumerator(atPath: path)
            while let element = enumerator?.nextObject() as? String {
                let filePath = path + "/" + element
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                    if !isDirectory.boolValue {
                        count += 1
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: filePath)
                            if let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
                                size += fileSize.int64Value
                                infos.append(FileInfo(path: filePath, size: fileSize.int64Value))
                            }
                        } catch {
                            print("Error getting file size for \(filePath): \(error)")
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.fileCount = count
                self.totalSize = size
                self.fileInfos = infos
                self.isLoading = false
            }
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 文件选择异步函数 openFilePanelAsync
func openFilePanelAsync(currentKeyWindow: NSWindow?) async throws -> [URL] {
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
            guard let window = currentKeyWindow else {
                continuation.resume(throwing: FileSelectionError.noActiveWindow)
                return
            }

            let openPanel = NSOpenPanel()
            openPanel.title = "Select Files"
            openPanel.prompt = "Open"
            openPanel.allowsMultipleSelection = true
            openPanel.canChooseDirectories = false
            openPanel.canChooseFiles = true

            // 支持更多音频格式
            openPanel.allowedContentTypes = [
                .mp3, .wav, .aiff, .video,
                UTType(filenameExtension: "m4a") ?? .audio,
                UTType(filenameExtension: "flac") ?? .audio,
                UTType(filenameExtension: "ogg") ?? .audio,
                UTType(filenameExtension: "aac") ?? .audio,
                UTType(filenameExtension: "mp4") ?? .video,
                UTType(filenameExtension: "mov") ?? .video,
            ]

            openPanel.beginSheetModal(for: window) { response in
                if response == .OK {
                    continuation.resume(returning: openPanel.urls)
                } else {
                    continuation.resume(throwing: FileSelectionError.userCancelled)
                }
            }
        }
    }
}

/// 在沙盒环境下，通过用户选择获取公开的文稿（Documents）目录 URL。
/// 这是一个异步操作，因为需要用户交互。
///
/// - Parameter completion: 回调闭包，返回获取到的 URL 或 nil。
@MainActor
func getPublicDocumentsDirectoryURL(completion: @escaping (URL?) -> Void) {
    Task { @MainActor in
        let url = await PermissionManager.shared.requestDocumentsFolderAccess()
        completion(url)
    }
}

/// 尝试从保存的书签中恢复对公开文稿目录的访问。
/// 首次运行或书签失效时，可能需要再次调用 `getPublicDocumentsDirectoryURL` 提示用户选择。
///
/// - Parameter completion: 回调闭包，返回获取到的 URL 或 nil。
@MainActor
func retrievePublicDocumentsDirectoryURLFromBookmark(completion: @escaping (URL?) -> Void) {
    Task { @MainActor in
        let url = await PermissionManager.shared.restoreDocumentsFolderAccess()
        completion(url)
    }
}

// 你可以在应用程序启动时尝试恢复访问，如果失败，则提示用户选择。
// 假设在你的 ContentView 或 AppDelegate 中：
@MainActor
func setupDocumentsAccess(viewModel: MainViewModel) {
    @AppStorage("exportPath") var exportPath: String = ""
    Task { @MainActor in
        if let url = await PermissionManager.shared.ensureDocumentsFolderAccess() {
            viewModel.publicDocumentsDirectoryURL = url
            if exportPath == "" || !FileManager.default.fileExists(atPath: exportPath) {
                exportPath = setupDefaultExportPath(publicDocumentsURL: url)
            }
        }
    }
}

// MARK: - 设置默认导出路径
func setupDefaultExportPath(publicDocumentsURL: URL) -> String {
    let exportPath = publicDocumentsURL.appendingPathComponent("transee_export").path
    if !FileManager.default.fileExists(atPath: exportPath) {
        try? FileManager.default.createDirectory(
            atPath: exportPath, withIntermediateDirectories: true, attributes: nil)
    }
    return exportPath
}

// MARK: - 自定义 DropDelegate
class FileDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool  // 用于高亮拖放区域
    @ObservedObject var viewModel: MainViewModel  // 访问 ViewModel

    // 允许的类型（例如，音频和视频）
    let allowedContentTypes: [UTType] = [.fileURL, .audio]
    init(isTargeted: Binding<Bool>, viewModel: MainViewModel) {
        _isTargeted = isTargeted
        self.viewModel = viewModel
    }
    // 1. 当可拖拽项进入拖放区域时调用
    func dropEntered(info: DropInfo) {
        isTargeted = true
        viewModel.lastDropError = nil  // 重置错误
    }
    // 2. 当可拖拽项在拖放区域内移动时调用
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // 验证文件类型，如果有效则显示复制操作，否则显示禁止
        if validateDrop(info: info) {
            viewModel.lastDropError = nil  // 清除之前的错误
            return DropProposal(operation: .copy)  // 允许复制
        } else {
            // 设置错误信息，以便在 UI 上显示
            viewModel.lastDropError = "Only audio or video files are allowed."
            return DropProposal(operation: .forbidden)  // 禁止拖放
        }
    }
    // 3. 验证拖拽数据是否可接受（核心逻辑）
    func validateDrop(info: DropInfo) -> Bool {
        // 遍历所有拖拽项
        let canHandleAll = info.itemProviders(for: [.fileURL]).allSatisfy { provider in
            // 如果能提供 fileURL，我们才检查它的实际类型
            // 注意：这里我们只能拿到 NSItemProvider，还不能完全加载文件内容来判断
            // 真正的文件类型检查会在 performDrop 中进行。
            // 但是，我们可以做一个初步检查，确保它至少是 fileURL
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        // 由于在 `validateDrop` 阶段，我们无法直接加载文件的 `URL` 并检查其 `UTType`
        // 这里的 `canHandleAll` 只能确保它是一个文件 URL。
        // 如果要更精确的预判断，可能需要依赖拖拽源提供的更具体的 `UTType`。
        // 但对于从 Finder 拖拽文件，`fileURL` 是主要类型。
        // 这里的 `validateDrop` 主要用于确认是文件。

        return canHandleAll  // 只要是文件URL就先允许拖入，具体类型在performDrop中检查
    }
    // 4. 当可拖拽项离开拖放区域时调用
    func dropExited(info: DropInfo) {
        isTargeted = false
        viewModel.lastDropError = nil  // 清除错误
    }
    // 5. 当用户放下可拖拽项时调用（核心数据加载）
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        viewModel.lastDropError = nil  // 重置错误信息
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }  // 没有文件 URL 提供者
        let dispatchGroup = DispatchGroup()
        var anyInvalidFileFound = false
        for provider in itemProviders {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                (item, error) in
                let isItemData = item is Data
                let resolvedURL: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    return item as? URL
                }()
                let unexpectedItemDescription = resolvedURL == nil ? String(describing: item) : nil

                DispatchQueue.main.async {
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("Error loading file URL: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            anyInvalidFileFound = true
                        }
                        self.viewModel.lastDropError = "Error loading file: \(error.localizedDescription)"
                        return
                    }
                    if let url = resolvedURL {
                        if isItemData {
                            print("Loaded file URL from Data: \(url.path)")
                        } else {
                            print("Loaded file URL from URL: \(url.path)")
                        }
                    } else {
                        print("Unexpected item type for fileURL: \(unexpectedItemDescription ?? "nil")")
                    }
                    /*
                    else {
                            print("Unexpected item type for fileURL: \(String(describing: item))")
                            anyInvalidFileFound = true
                            self.viewModel.lastDropError = "Failed to get file URL from dropped item."
                            return
                    }
                    */
                    if let fileURL = resolvedURL {

                        // 假设 fileURL 是从 NSItemProvider 获取到的
                        let coordinator = NSFileCoordinator()
                        var coordinatedError: NSError?
                        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatedError) {
                            (resolvedURL) in
                            // resolvedURL 是一个带有安全作用域权限的 URL，你可以在这个闭包里安全地访问文件
                            do {
                                let resourceValues = try resolvedURL.resourceValues(forKeys: [
                                    .isDirectoryKey, .fileSizeKey,
                                ])
                                if let isDirectory = resourceValues.isDirectory, isDirectory {
                                    print("DEBUG: Dropped item is a directory: \(resolvedURL.path)")
                                    // 处理目录（如果你的应用支持拖放目录）
                                } else if let fileSize = resourceValues.fileSize {

                                    let fileType =
                                        resourceValues.contentType ?? UTType(
                                            filenameExtension: resolvedURL.pathExtension) ?? .data
                                    print(
                                        "DEBUG: Successfully accessed file: \(resolvedURL.path), size: \(fileSize) bytes, type: \(fileType.identifier)"
                                    )
                                    // ... 将文件添加到你的 ViewModel ...
                                    self.viewModel.selectedAudioFiles.append(
                                        SelectedAudioFile(
                                            fileUrl: resolvedURL,
                                            fileBaseName: resolvedURL.lastPathComponent,
                                            fileSize: fileSize,
                                            fileType: fileType,
                                            mediaType: .audio
                                        ))
                                }
                            } catch {
                                print(
                                    "ERROR: Failed to read file details or content after coordination: \(error.localizedDescription)"
                                )
                                self.viewModel.lastDropError =
                                    "Failed to process dropped file: \(error.localizedDescription)"
                            }
                        }
                        if let error = coordinatedError {
                            print(
                                "ERROR: NSFileCoordinator failed to coordinate reading: \(error.localizedDescription)"
                            )
                            self.viewModel.lastDropError =
                                "Failed to coordinate access for dropped file: \(error.localizedDescription)"
                        }

                        // 在这里尝试启动安全作用域访问
                        /*
                        let accessGranted = url?.startAccessingSecurityScopedResource() ?? false
                        print("Access granted: \(accessGranted)")
                        if !accessGranted {
                                print("@1Failed to gain access to security scoped resource for URL: \(url?.path ?? "nil")")
                                anyInvalidFileFound = true
                                self.viewModel.lastDropError = "Failed to access dropped file: \(url?.lastPathComponent ?? "nil")."
                                // 由于无法访问，不再尝试获取文件信息或添加到ViewModel
                                return
                        }
                        */

                        // 确保在任何退出路径上停止访问，除非你希望长期持有
                        // 对于简单的文件信息获取，可以在这里立即停止
                        // 但如果你后续还需要访问，则需要更复杂的管理
                        // 暂时我们先在这里获取信息，并尝试停止访问
                        // 如果后续转写还需要，则需要在转写服务中再次 startAccessing
                        // MARK: - 使用 defer 确保在函数退出时停止访问

                        // 无论下面代码是正常执行，还是抛出错误，都会执行 defer 块中的内容
                        /*
                        defer {
                                url?.stopAccessingSecurityScopedResource()
                                print("Stopped accessing security scoped resource for URL: \(url?.path ?? "nil")")
                        }
                        
                        do {
                                let resourceValues = try url?.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]) ?? URLResourceValues()
                                let fileType = resourceValues.contentType ?? UTType(filenameExtension: url?.pathExtension ?? "") ?? .data
                                let fileSize = resourceValues.fileSize ?? 0
                                // 最终的文件类型验证
                                if self.allowedContentTypes.contains(where: { fileType.conforms(to: $0) }) {
                                        let success = url?.startAccessingSecurityScopedResource() ?? false
                                        if !success {
                                                print("@2Failed to gain access to security scoped resource for URL: \(url?.path ?? "nil")")
                                                anyInvalidFileFound = true
                                                self.viewModel.lastDropError = "Failed to access dropped file."
                                                return
                                        }
                                        self.viewModel.selectedAudioFiles.append(SelectedAudioFile(
                                                fileUrl: url ?? URL(fileURLWithPath: ""),
                                                fileBaseName: url?.lastPathComponent ?? "nil",
                                                fileSize: fileSize,
                                                fileType: fileType
                                        ))
                                        print("Added valid file: \(url?.lastPathComponent ?? "nil")")
                                } else {
                                        print("Dropped file '\(url?.lastPathComponent ?? "nil")' is not an allowed type (\(fileType.localizedDescription ?? "unknown")).")
                                        anyInvalidFileFound = true
                                        self.viewModel.lastDropError = "File '\(url?.lastPathComponent ?? "nil")' is not an allowed type."
                                }
                        } catch {
                                print("Error getting file info for \(url?.path ?? "nil"): \(error.localizedDescription)")
                                anyInvalidFileFound = true
                                self.viewModel.lastDropError = "Error processing file '\(url?.lastPathComponent ?? "nil")': \(error.localizedDescription)"
                        }
                        */
                    }
                }
            }
        }
        dispatchGroup.notify(queue: .main) {
            // 所有文件处理完毕
            if anyInvalidFileFound {
                // 如果有无效文件，且没有具体的错误信息，则给一个通用错误
                if self.viewModel.lastDropError == nil {
                    self.viewModel.lastDropError =
                        "Some dropped files were not valid or could not be processed."
                }
            } else {
                self.viewModel.transcribeFileViewState = .selectFiles
                self.viewModel.lastDropError = nil  // 成功则清除错误
            }
        }
        return true  // 返回 true 表示我们正在处理拖放操作
    }
}

@MainActor
func selectFolderURL(initialDirectory: URL? = nil) -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.canCreateDirectories = true
    openPanel.allowsMultipleSelection = false
    if let initialDirectory = initialDirectory {
        openPanel.directoryURL = initialDirectory
    }
    return openPanel.runModal() == .OK ? openPanel.url : nil
}

/// 显示文件夹选择器，允许用户选择一个文件夹。
/// - Returns: 用户选择的文件夹路径。
@MainActor
func showFolderPicker(completion: @escaping (URL?) -> Void) {
    // 创建 NSOpenPanel 实例
    let openPanel = NSOpenPanel()

    // 设置面板属性
    openPanel.canChooseFiles = false  // 禁止选择文件
    openPanel.canChooseDirectories = true  // 允许选择目录
    openPanel.canCreateDirectories = true  // 允许创建新目录
    openPanel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("MySubFolder")

    // 显示面板并等待用户响应
    openPanel.begin { (result) -> Void in
        if result == .OK, let selectedDirectoryURL = openPanel.url {
            print("用户选择的文件夹路径：\(selectedDirectoryURL)")
            // 调用完成闭包，传入所选文件夹的 URL
            completion(selectedDirectoryURL)
        } else {
            print("用户取消了文件夹选择")
            // 如果用户没有选择任何文件夹，则传入 nil
            completion(nil)
        }
    }
}

/// 扫描指定路径下的文件，并返回文件数量和总大小。
/// - Parameters:
///   - path: 要扫描的路径（可以是文件或目录）。
///   - includeSubdirectories: 是否包含子目录中的文件。默认为 `true`。
///   - includeHiddenFiles: 是否包含隐藏文件（以点开头的文件或目录）。默认为 `false`。
/// - Returns: 一个元组，包含文件数量和总大小（以字节为单位）。
/// - Throws: `FileSystemError` 如果路径无效或文件系统操作失败。
func getFileCountAndTotalSize(
    at path: String,
    includeSubdirectories: Bool = true,
    includeHiddenFiles: Bool = false
) throws -> (fileCount: Int, totalSize: UInt64) {
    let fileManager = FileManager.default
    var fileCount: Int = 0
    var totalSize: UInt64 = 0
    // 检查路径是否存在
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw FileSystemError.invalidPath(path)
    }
    // 如果路径是单个文件
    if !isDirectory.boolValue {
        // 如果是隐藏文件且不包含隐藏文件，则直接返回0
        if !includeHiddenFiles && (path as NSString).lastPathComponent.hasPrefix(".") {
            return (0, 0)
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            fileCount = 1
            // FileAttributeKey.size 返回的类型在不同平台可能是 NSNumber
            if let number = attributes[FileAttributeKey.size] as? NSNumber {
                totalSize = number.uint64Value
            } else if let intSize = attributes[FileAttributeKey.size] as? Int {
                totalSize = UInt64(intSize)
            }
        } catch {
            throw FileSystemError.fileAccessDenied(path, error)
        }
        return (fileCount, totalSize)
    }
    // 如果路径是目录
    var enumeratorOptions: FileManager.DirectoryEnumerationOptions = []
    if includeSubdirectories {
        // 不设置 skipDescendants 选项，表示遍历子目录
        // 保持默认
    } else {
        // 设置 skipDescendants 选项，表示不遍历子目录
        // 注意：在这种情况下，我们仍然需要遍历当前目录的文件，
        // 但 FileManager.default.enumerator(atPath:) 默认会处理这种情况，
        // 只要我们不递归调用。
        enumeratorOptions = .skipsSubdirectoryDescendants  // 只列出当前目录项，不深入
    }

    // 如果不包含隐藏文件，添加跳过隐藏文件的选项
    // 使用 .skipsHiddenFiles 可以跳过隐藏文件和目录；仍将手动检查以更稳妥
    if !includeHiddenFiles {
        enumeratorOptions.insert(.skipsHiddenFiles)
    }
    // 不全局跳过包目录，改为遇到包时局部处理以准确统计其大小
    guard
        let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .fileSizeKey, .isDirectoryKey, .isHiddenKey, .isPackageKey, .totalFileAllocatedSizeKey,
            ],
            options: enumeratorOptions,
            errorHandler: { url, error in
                print("Error enumerating \(url.lastPathComponent): \(error.localizedDescription)")
                return true  // 返回 true 继续枚举
            }
        )
    else {
        throw FileSystemError.directoryEnumerationFailed(
            path,
            NSError(
                domain: "FileManager", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator"]))
    }
    for case let fileURL as URL in enumerator {
        // 始终忽略当前目录和父目录引用
        let name = fileURL.lastPathComponent
        if name == "." || name == ".." {
            // 防止深入其子项（双保险）
            enumerator.skipDescendants()
            continue
        }
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .fileSizeKey, .isDirectoryKey, .isHiddenKey, .isPackageKey, .totalFileAllocatedSizeKey,
            ])
            let isDir = resourceValues.isDirectory ?? false
            let isHidden = resourceValues.isHidden ?? fileURL.lastPathComponent.hasPrefix(".")
            let isPackage = resourceValues.isPackage ?? false

            // 手动过滤隐藏文件/目录（双保险）；如果是隐藏目录，阻止深入
            if !includeHiddenFiles && isHidden {
                if isDir {
                    enumerator.skipDescendants()
                }
                continue
            }

            if !isDir {  // 只处理文件
                if let fileSize = resourceValues.fileSize {
                    fileCount += 1
                    totalSize += UInt64(fileSize)
                    print("@@@DEBUG: Url: \(fileURL.path), fileSize: \(fileSize)")
                }
            } else if isDir {
                // 包目录作为单个项计数，但递归内部文件以准确统计大小
                if isPackage {
                    enumerator.skipDescendants()
                    fileCount += 1
                    totalSize += directoryTotalSize(url: fileURL, includeHiddenFiles: includeHiddenFiles)
                    continue
                }
                if !includeSubdirectories {
                    // 如果是目录，且不包含子目录，则需要跳过这个目录下的文件。
                    // enumeratorOptions = .skipsSubdirectoryDescendants 已经处理了子目录遍历，
                    // 这里的逻辑主要是确保在不包含子目录的情况下，不会把子目录本身算作文件。
                    // 且对于 .skipsSubdirectoryDescendants 选项，enumerator 会返回目录本身，但不会进入其内部。
                    // 所以在这里我们不需要对目录进行额外的处理。

                    // 但是，如果 includeSubdirectories 为 false，我们需要手动阻止 enumerator 深入子目录。
                    // 幸运的是，FileManager.DirectoryEnumerationOptions.skipsSubdirectoryDescendants 已经做到了。
                    // 这里的 `continue` 是为了防止目录被误算为文件
                    continue
                }
            }
        } catch {
            // 如果无法获取文件属性，记录错误并继续
            print(
                "Error getting attributes for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            continue
        }
    }
    return (fileCount, totalSize)
}

// 计算目录（包含包目录）内所有文件的总大小，但不拆解为单个文件计数
private func directoryTotalSize(url: URL, includeHiddenFiles: Bool) -> UInt64 {
    let fileManager = FileManager.default
    var total: UInt64 = 0
    let options: FileManager.DirectoryEnumerationOptions =
        includeHiddenFiles ? [] : [.skipsHiddenFiles]
    guard
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey, .isDirectoryKey, .isHiddenKey, .totalFileAllocatedSizeKey,
            ],
            options: options,
            errorHandler: { u, error in
                print("Error enumerating for size at \(u.lastPathComponent): \(error.localizedDescription)")
                return true
            }
        )
    else {
        return 0
    }
    for case let u as URL in enumerator {
        let name = u.lastPathComponent
        if name == "." || name == ".." {
            enumerator.skipDescendants()
            continue
        }
        do {
            let values = try u.resourceValues(forKeys: [
                .fileSizeKey, .isDirectoryKey, .isHiddenKey, .totalFileAllocatedSizeKey,
            ])
            let isDir = values.isDirectory ?? false
            let isHidden = values.isHidden ?? u.lastPathComponent.hasPrefix(".")
            if !includeHiddenFiles && isHidden {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if !isDir {
                let component = (values.totalFileAllocatedSize ?? values.fileSize) ?? 0
                total += UInt64(component)
            }
        } catch {
            print("Error getting file size for \(u.path): \(error.localizedDescription)")
            continue
        }
    }
    return total
}

// 获取文档目录的URL
/// 此函数用于获取应用程序的文档目录URL。文档目录是一个特殊的目录，用于存储应用程序生成的文件，
/// 这些文件对用户可见（如文档、配置文件等）。
/// - Returns: 文档目录的URL，如果获取失败则返回nil
func getDocumentsDirectoryURL() -> URL? {
    // 获取文件管理器实例
    let fileManager = FileManager.default
    do {
        // 使用 .documentDirectory 获取 Documents 目录
        // 使用 .userDomainMask 指定用户域
        // appropriateFor: nil 表示不指定特定URL来查找
        // create: false 表示如果目录不存在则不创建它（通常 Documents 目录总是存在的）
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        // 直接返回 URL 对象
        return documentsURL
    } catch {
        print("Error getting Documents directory URL: \(error)")
        return nil
    }
}

/// 变通的格式化方法，可选择显示小时，但会在小时为0时不显示 "00:"
/// 例如：50秒 -> "00:50"，50分钟 -> "50:00"，1小时-> "01:00:00"
/// 并不强制显示小时，但一旦显示就会补零至两位
/// 格式化时间类型
enum FormatTimeType {
    case forSrt
    case forTable
}

func formatSmartTime(seconds: Double, type: FormatTimeType = .forTable) -> String {
    let totalSeconds = Int(seconds)
    let milliseconds = Int((seconds - Double(totalSeconds)) * 1000)

    guard totalSeconds >= 0 else { return "00:00" }  // 处理负数情况

    let millisecondsStr = String(format: "%03d", milliseconds)
    let seconds = totalSeconds % 60
    let minutes = (totalSeconds / 60) % 60
    let hours = totalSeconds / 3600
    switch type {
    case .forSrt:
        return String(format: "%02d:%02d:%02d,%@", hours, minutes, seconds, millisecondsStr)
    case .forTable:
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    /*
    if hours > 0 {
            return String(format: "%02d:%02d:%02d,%@", hours, minutes, seconds, millisecondsStr)
    } else {
            return String(format: "%02d:%02d,%@", minutes, seconds, millisecondsStr)
    }
    */
}

//
//  AudioInputManager.swift
//  transee
//
//  Created by gavanwang on 2026/2/13.
//

import Foundation
import CoreAudio
import AVFoundation   // 新增：用于权限查询

struct AudioDeviceInfo {
    let name: String
    let id: AudioDeviceID
}


// MARK: - Audio Input Device Management

/// 管理音频输入设备的类
///
/// 该类提供了查询和设置系统默认音频输入设备的功能。
class AudioInputDeviceManager {

    /// 获取系统默认音频输入设备的名称和 ID
    ///
    /// 该函数使用 CoreAudio API 查询系统硬件属性，以确定当前被设置为默认输入的设备。
    ///
    /// - Returns: 一个包含设备名称和设备 ID 的元组；如果获取失败则返回 nil。
    func getDefaultAudioInputDevice() -> AudioDeviceInfo? {
        //return getSystemDefaultAudioInputDeviceName()
        // 1. 构建属性地址以查询默认输入设备
        // kAudioHardwarePropertyDefaultInputDevice: 请求默认输入设备的 ID
        // kAudioObjectPropertyScopeGlobal: 全局作用域
        // kAudioObjectPropertyElementMain: 主元素
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        // 2. 获取默认输入设备的 ID
        // kAudioObjectSystemObject: 代表整个系统音频硬件的对象
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        // 检查是否成功获取设备 ID
        guard status == noErr else { return nil }

        // 3. 准备查询设备名称
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        // kAudioDevicePropertyDeviceNameCFString: 请求设备的名称（作为 CFString）
        var nameProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 4. 获取设备名称
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameProperty,
            0,
            nil,
            &nameSize,
            &name
        )

        // 5. 处理结果
        // takeRetainedValue(): 获取 CFString 的值并负责释放内存
        if nameStatus == noErr, let nameUnmanaged = name {
            return AudioDeviceInfo(name: nameUnmanaged.takeRetainedValue() as String, id: deviceID)
        }
        return nil
    }

    /// 获取所有音频输入设备列表
    ///
    /// 该函数使用 CoreAudio API 枚举系统中所有可用的音频输入设备。
    ///
    /// - Returns: 包含所有输入设备信息的数组；如果获取失败则返回空数组。
    func getAudioInputDevices() -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []

        // 1. 构建属性地址以查询所有音频设备
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(0)

        // 2. 先获取设备列表所需的数据大小
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr, dataSize > 0 else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        // 3. 获取所有设备 ID
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else { return devices }

        // 4. 遍历设备，筛选输入设备
        for deviceID in deviceIDs {
            if isInputDevice(deviceID: deviceID), let info = getDeviceInfo(deviceID: deviceID) {
                devices.append(info)
            }
        }

        return devices
    }

    /// 判断设备是否为输入设备
    private func isInputDevice(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(0)
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList)
        guard dataStatus == noErr else { return false }

        let audioBufferList = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        return audioBufferList.pointee.mNumberBuffers > 0
    }

    /// 获取设备名称和 ID
    private func getDeviceInfo(deviceID: AudioObjectID) -> AudioDeviceInfo? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr, let nameUnmanaged = name else { return nil }

        return AudioDeviceInfo(name: nameUnmanaged.takeRetainedValue() as String, id: deviceID)
    }

    /// 查询当前应用是否已获得麦克风（音频输入）权限
    ///
    /// - Returns: 授权状态（.granted / .denied / .undetermined / .restricted）
    func checkAudioInputAuthorization() -> Bool {
        // macOS 上使用 CoreAudio 无法直接查询“麦克风权限”，
        // 只能尝试打开默认输入设备；若用户拒绝，则打开失败。
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        // 如果无法获取默认输入设备，视为无权限
        return status == noErr && deviceID != kAudioObjectUnknown
    }
    
    // MARK: - Audio Input Monitoring
    
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    /// 开始监听默认音频输入设备的变化
    /// - Parameter onChange: 当设备发生变化时的回调，返回新的默认设备信息
    func startMonitoringDefaultInputDevice(onChange: @escaping @Sendable (AudioDeviceInfo?) -> Void) {
        // 先移除旧的监听器（如果有），防止重复注册
        stopMonitoringDefaultInputDevice()
        
        // 1. 定义要监听的属性：默认输入设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 2. 创建监听回调块
        // 注意：这里需要引用 self 来调用获取设备的方法，所以要小心循环引用
        let listener: AudioObjectPropertyListenerBlock = { [weak self] (numberAddresses, addresses) in
            guard let self = self else { return }
            
            // 获取新的默认设备信息
            let deviceInfo = self.getDefaultAudioInputDevice()
            
            // 切换到主线程调用回调，方便 UI 更新
            Task { @MainActor in
                onChange(deviceInfo)
            }
        }
        
        self.listenerBlock = listener
        
        // 3. 注册监听器
        // 使用 AudioObjectAddPropertyListenerBlock (macOS 10.7+)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil, // nil 表示在内部队列调用
            listener
        )
        
        if status != noErr {
            print("Error adding audio property listener: \(status)")
            self.listenerBlock = nil
        }
    }
    
    /// 停止监听
    func stopMonitoringDefaultInputDevice() {
        guard let listener = listenerBlock else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            listener
        )
        
        self.listenerBlock = nil
    }
}

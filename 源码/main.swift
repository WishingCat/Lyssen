// Lyssen — 蓝牙麦克风守护
//
// 作用:常驻后台,监听系统音频输入设备。
// 一旦发现"当前输入设备"被切到了蓝牙耳机,就立刻切回 MacBook 内置麦克风。
// 这样听音乐时输出端能保持 A2DP 高音质,不会因为麦克风占用被降级为通话音质。
//
// 界面:点开 app 弹出一个浅色设置面板,
//       Airalo 风格 —— 暖色背景 + 白色分组卡片 + 橘色主操作。

import AppKit
import SwiftUI
import Combine
import CoreAudio
import ServiceManagement

// MARK: - CoreAudio 辅助函数

/// 读取设备名字
func deviceName(_ id: AudioDeviceID) -> String {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    if status == noErr, let cf = name?.takeRetainedValue() {
        return cf as String
    }
    return "未知设备"
}

/// 读取设备的传输类型(内置 / 蓝牙 / USB ...)
func transportType(_ id: AudioDeviceID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
    return transport
}

/// 该设备是否有输入声道(用来区分"麦克风"和"纯扬声器")
func hasInputChannels(_ id: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
        return false
    }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else {
        return false
    }
    let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
    var channels = 0
    for buf in UnsafeMutableAudioBufferListPointer(abl) {
        channels += Int(buf.mNumberChannels)
    }
    return channels > 0
}

/// 列出系统里所有音频设备
func allDevices() -> [AudioDeviceID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let sys = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &devices)
    return devices
}

/// 找到内置麦克风
func findBuiltinMic() -> AudioDeviceID? {
    for dev in allDevices() {
        if transportType(dev) == kAudioDeviceTransportTypeBuiltIn && hasInputChannels(dev) {
            return dev
        }
    }
    return nil
}

/// 当前默认输入设备
func defaultInputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    return dev
}

/// 当前默认输出设备
func defaultOutputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    return dev
}

/// 设置默认输入设备
@discardableResult
func setDefaultInput(_ id: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = id
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
    return status == noErr
}

/// 是否为蓝牙传输
func isBluetooth(_ id: AudioDeviceID) -> Bool {
    let t = transportType(id)
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
}

// MARK: - 本地化文案

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
    var badge: String { self == .zh ? "中文" : "EN" }

    var next: AppLanguage {
        self == .zh ? .en : .zh
    }

    var copy: AppCopy {
        switch self {
        case .zh:
            return AppCopy(
                homeTitle: "音质守护",
                homeSubtitle: "保持蓝牙耳机高音质播放",
                guardOn: "守护中",
                guardOff: "已暂停",
                moreSettings: "设置",
                advancedSettings: "高级设置",
                done: "完成",
                settings: "设置",
                launchAtLogin: "开机启动",
                guardBluetoothMic: "蓝牙麦克风守护",
                blockExternalMics: "阻止外置麦克风",
                showWindowOnStart: "启动时显示窗口",
                currentInput: "当前输入",
                currentOutput: "当前输出",
                bluetoothDevice: "蓝牙设备",
                protectedSwitches: "守护次数",
                unknown: "未知",
                notConnected: "未连接",
                explanation: "Lyssen 会把 Mac 输入保持在内置麦克风,让蓝牙耳机维持高音质播放模式。",
                quitLyssen: "退出 Lyssen",
                help: "帮助与限制",
                privacy: "隐私说明",
                about: "关于 Lyssen",
                copyDiagnostics: "复制诊断信息",
                ready: "守护已就绪",
                diagnosticsCopied: "诊断信息已复制到剪贴板",
                ok: "好的",
                helpTitle: "帮助与限制",
                helpMessage: "Lyssen 会监听系统默认输入设备。一旦输入被切到蓝牙耳机,它会自动切回内置麦克风。若某个会议 App 在自己的设置里强制选择耳机麦克风,仍需要在该 App 内单独修改。",
                privacyTitle: "隐私说明",
                privacyMessage: "Lyssen 不联网、不收集数据、不使用第三方服务。设置仅保存在本机 UserDefaults 中;诊断信息只在你点击复制时写入剪贴板。",
                aboutTitle: "关于 Lyssen",
                versionLabel: "版本")
        case .en:
            return AppCopy(
                homeTitle: "Audio Guard",
                homeSubtitle: "Keep Bluetooth listening clear",
                guardOn: "Guarding",
                guardOff: "Paused",
                moreSettings: "Settings",
                advancedSettings: "Advanced",
                done: "Done",
                settings: "Settings",
                launchAtLogin: "Launch at Login",
                guardBluetoothMic: "Guard Bluetooth Mic",
                blockExternalMics: "Block External Mics",
                showWindowOnStart: "Show Window on Start",
                currentInput: "Current Input",
                currentOutput: "Current Output",
                bluetoothDevice: "Bluetooth Device",
                protectedSwitches: "Protected Switches",
                unknown: "Unknown",
                notConnected: "Not Connected",
                explanation: "Lyssen keeps your Mac input on the built-in microphone, so Bluetooth headphones stay in high-quality listening mode.",
                quitLyssen: "Quit Lyssen",
                help: "Help & Limits",
                privacy: "Privacy",
                about: "About Lyssen",
                copyDiagnostics: "Copy Diagnostics",
                ready: "Guard ready",
                diagnosticsCopied: "Diagnostics copied to clipboard",
                ok: "OK",
                helpTitle: "Help & Limits",
                helpMessage: "Lyssen watches the system default input device. If Bluetooth headphone input becomes active, it switches input back to the built-in microphone. If a meeting app forces its own microphone choice, change that inside the meeting app.",
                privacyTitle: "Privacy",
                privacyMessage: "Lyssen does not use the network, collect data, or use third-party services. Settings stay locally in UserDefaults; diagnostics are copied only when you choose to copy them.",
                aboutTitle: "About Lyssen",
                versionLabel: "Version")
        }
    }
}

struct AppCopy {
    let homeTitle: String
    let homeSubtitle: String
    let guardOn: String
    let guardOff: String
    let moreSettings: String
    let advancedSettings: String
    let done: String
    let settings: String
    let launchAtLogin: String
    let guardBluetoothMic: String
    let blockExternalMics: String
    let showWindowOnStart: String
    let currentInput: String
    let currentOutput: String
    let bluetoothDevice: String
    let protectedSwitches: String
    let unknown: String
    let notConnected: String
    let explanation: String
    let quitLyssen: String
    let help: String
    let privacy: String
    let about: String
    let copyDiagnostics: String
    let ready: String
    let diagnosticsCopied: String
    let ok: String
    let helpTitle: String
    let helpMessage: String
    let privacyTitle: String
    let privacyMessage: String
    let aboutTitle: String
    let versionLabel: String
}

enum InfoNotice: Identifiable {
    case help
    case privacy
    case about

    var id: String {
        switch self {
        case .help: return "help"
        case .privacy: return "privacy"
        case .about: return "about"
        }
    }
}

// MARK: - 数据模型(守护逻辑 + 设置)

final class GuardModel: ObservableObject {

    // 可配置项(写入 UserDefaults 持久化)
    @Published var guardEnabled: Bool {
        didSet { defaults.set(guardEnabled, forKey: "guardEnabled"); enforce() }
    }
    @Published var interceptAllExternal: Bool {
        didSet { defaults.set(interceptAllExternal, forKey: "interceptAllExternal"); enforce() }
    }
    @Published var showWindowOnLaunch: Bool {
        didSet { defaults.set(showWindowOnLaunch, forKey: "showWindowOnLaunch") }
    }
    @Published var launchAtLogin: Bool {
        didSet { if !syncingLogin { applyLaunchAtLogin() } }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            lastInfo = language.copy.ready
        }
    }

    // 只读状态(给界面展示)
    @Published private(set) var switchCount: Int = 0
    @Published private(set) var lastInfo: String = "守护已就绪"
    @Published private(set) var currentInputName: String = ""
    @Published private(set) var currentOutputName: String = ""
    @Published private(set) var bluetoothDeviceName: String? = nil

    private let defaults = UserDefaults.standard
    private var builtinMic: AudioDeviceID = 0
    private var syncingLogin = false

    init() {
        let d = UserDefaults.standard
        let legacy = UserDefaults(suiteName: "com.wishingcat.lyssen")
        func stored(_ key: String) -> Any? {
            d.object(forKey: key) ?? legacy?.object(forKey: key)
        }

        guardEnabled        = stored("guardEnabled") as? Bool ?? true
        interceptAllExternal = stored("interceptAllExternal") as? Bool ?? false
        showWindowOnLaunch  = stored("showWindowOnLaunch") as? Bool ?? false
        launchAtLogin       = false   // 启动后由 refreshLoginStatus() 校准
        language            = AppLanguage(rawValue: (stored("language") as? String) ?? "") ?? .zh
        lastInfo            = language.copy.ready
    }

    /// 启动守护:定位内置麦克风、注册监听、立即执行一次
    func start() {
        builtinMic = findBuiltinMic() ?? 0
        refreshLoginStatus()

        let sys = AudioObjectID(kAudioObjectSystemObject)

        // 监听 1:默认输入设备变化
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(sys, &inputAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.enforce()
        }

        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(sys, &outputAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.refreshDevices()
        }

        // 监听 2:设备列表变化(耳机接入/移除瞬间)
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(sys, &listAddr, DispatchQueue.main) { [weak self] _, _ in
            guard let self else { return }
            if let mic = findBuiltinMic() { self.builtinMic = mic }
            self.enforce()
        }

        refreshDevices()
        enforce()
    }

    /// 判断某输入设备是否"应当被拦截"
    private func isUndesired(_ id: AudioDeviceID) -> Bool {
        if interceptAllExternal {
            return transportType(id) != kAudioDeviceTransportTypeBuiltIn
        } else {
            return isBluetooth(id)
        }
    }

    /// 核心:若当前输入不该用,就切回内置麦克风
    func enforce() {
        refreshDevices()
        guard guardEnabled else { return }

        let current = defaultInputDevice()
        guard isUndesired(current) else { return }

        if builtinMic == 0 { builtinMic = findBuiltinMic() ?? 0 }
        guard builtinMic != 0, current != builtinMic else { return }

        let from = deviceName(current)
        if setDefaultInput(builtinMic) {
            switchCount += 1
            lastInfo = language == .zh
                ? "已把输入从「\(from)」切回内置麦克风"
                : "Input switched from \(from) to the built-in microphone"
            currentInputName = deviceName(builtinMic)
        }
    }

    func copyDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let diagnostics = """
        Lyssen Diagnostics
        Version: \(version) (\(build))
        Guard Enabled: \(guardEnabled)
        Launch at Login: \(launchAtLogin)
        Intercept All External: \(interceptAllExternal)
        Show Window on Launch: \(showWindowOnLaunch)
        Current Input: \(currentInputName)
        Current Output: \(currentOutputName)
        Bluetooth Device: \(bluetoothDeviceName ?? "None")
        Protected Switches: \(switchCount)
        Last Status: \(lastInfo)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        lastInfo = language.copy.diagnosticsCopied
    }

    /// 刷新展示用的设备信息
    private func refreshDevices() {
        currentInputName = deviceName(defaultInputDevice())
        currentOutputName = deviceName(defaultOutputDevice())
        var bt: String? = nil
        for d in allDevices() where isBluetooth(d) {
            bt = deviceName(d); break
        }
        bluetoothDeviceName = bt
        if builtinMic == 0 { builtinMic = findBuiltinMic() ?? 0 }
    }

    // MARK: 开机自启(ServiceManagement)

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastInfo = language == .zh
                ? "设置开机启动失败:\(error.localizedDescription)"
                : "Launch at login failed: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        syncingLogin = true
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        syncingLogin = false
    }
}

// MARK: - 调色板(Airalo 截图风格)

extension Color {
    static let bwCanvas     = Color(red: 0.996, green: 0.955, blue: 0.922)
    static let bwInk        = Color(red: 0.120, green: 0.135, blue: 0.140)
    static let bwNavy       = Color(red: 0.984, green: 0.925, blue: 0.875)
    static let bwPanel      = Color.white
    static let bwPanelLight = Color(red: 0.988, green: 0.962, blue: 0.940)
    static let bwText       = Color(red: 0.120, green: 0.135, blue: 0.140)
    static let bwMuted      = Color(red: 0.500, green: 0.525, blue: 0.540)
    static let bwGreen      = Color(red: 0.080, green: 0.720, blue: 0.660)
    static let bwOrange     = Color(red: 1.000, green: 0.480, blue: 0.120)
    static let bwOrangeSoft = Color(red: 1.000, green: 0.905, blue: 0.820)
    static let bwLine       = Color(red: 0.905, green: 0.855, blue: 0.815)
    static let bwDanger     = Color(red: 0.770, green: 0.180, blue: 0.190)
}

// MARK: - Airalo 风格组件

struct BreathwrkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(configuration.isOn ? Color.bwOrange : Color(red: 0.875, green: 0.875, blue: 0.875))
                .frame(width: 44, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct BreathwrkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.bwCanvas,
                    Color(red: 1.000, green: 0.975, blue: 0.952),
                    Color.bwNavy
                ],
                startPoint: .top,
                endPoint: .bottom)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bwOrange.opacity(0.16))
                .frame(width: 72, height: 18)
                .rotationEffect(.degrees(22))
                .offset(x: 188, y: -236)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.bwGreen.opacity(0.14))
                .frame(width: 62, height: 18)
                .rotationEffect(.degrees(-26))
                .offset(x: -210, y: -118)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.700, green: 0.900, blue: 0.870).opacity(0.18))
                .frame(width: 70, height: 20)
                .rotationEffect(.degrees(18))
                .offset(x: -190, y: 224)
        }
        .ignoresSafeArea()
    }
}

struct BreathwrkTopBar: View {
    @Binding var language: AppLanguage
    var leadingSymbol: String = "line.3.horizontal"
    var leadingAction: () -> Void = {}

    var body: some View {
        HStack {
            Button(action: leadingAction) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.bwText)
                    .frame(width: 34, height: 34)
                    .background(Color.bwPanel, in: Circle())
                    .overlay(Circle().stroke(Color.bwLine.opacity(0.70), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("LYSSEN")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.bwOrange,
                            Color.bwGreen
                        ],
                        startPoint: .leading,
                        endPoint: .trailing)
                )

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    language = language.next
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .bold))
                    Text(language.badge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.bwText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.bwPanel, in: Capsule())
                .overlay(Capsule().stroke(Color.bwLine.opacity(0.70), lineWidth: 1))
                .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(width: 78, alignment: .trailing)
        }
        .foregroundStyle(Color.bwText)
    }
}

struct BreathwrkSheet<Content: View>: View {
    var showHandle = false
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if showHandle {
                Capsule()
                    .fill(Color.bwLine)
                    .frame(width: 80, height: 4)
                    .padding(.bottom, 14)
            }

            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bwPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.bwLine.opacity(0.80), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.060), radius: 18, y: 8)
        )
    }
}

struct BreathwrkPrimaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.bwOrange, in: Capsule())
                .shadow(color: Color.bwOrange.opacity(0.25), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct BreathwrkSecondaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.bwPanel, in: Capsule())
                .overlay(Capsule().stroke(Color.bwLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct LyssenLogoMark: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bwOrange,
                                Color.bwGreen
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                    )
                    .overlay {
                        Text("L")
                            .font(.system(size: size * 0.56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .shadow(color: Color.bwOrange.opacity(0.16), radius: 14, y: 7)
    }
}

// MARK: - 设置面板

enum SettingsPage {
    case home
    case more
}

struct SettingsView: View {
    @EnvironmentObject var model: GuardModel
    @State private var notice: InfoNotice?
    @State private var page: SettingsPage = .home

    var body: some View {
        ZStack {
            BreathwrkBackground()

            VStack(spacing: 0) {
                BreathwrkTopBar(
                    language: $model.language,
                    leadingSymbol: page == .home ? "gearshape.fill" : "chevron.left",
                    leadingAction: {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                            page = page == .home ? .more : .home
                        }
                    })
                    .padding(.horizontal, 32)
                    .padding(.top, 28)

                Group {
                    if page == .home {
                        homeContent(model.language.copy)
                    } else {
                        moreContent(model.language.copy)
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 0)
            }
        }
        .frame(width: 560, height: 560)
        .alert(item: $notice) { item in
            Alert(
                title: Text(alertTitle(item)),
                message: Text(alertMessage(item)),
                dismissButton: .default(Text(model.language.copy.ok))
            )
        }
    }

    private func homeContent(_ copy: AppCopy) -> some View {
        VStack(spacing: 12) {
            heroCard(copy)
            guardControl(copy)
            deviceSummary(copy)
            settingsEntry(copy)
            statusBanner(copy)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }

    private func heroCard(_ copy: AppCopy) -> some View {
        BreathwrkSheet(padding: 18) {
            HStack(spacing: 16) {
                LyssenLogoMark(size: 70)

                VStack(alignment: .leading, spacing: 6) {
                    Text("LYSSEN")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.bwOrange, Color.bwGreen],
                                startPoint: .leading,
                                endPoint: .trailing)
                        )

                    Text(copy.homeSubtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.bwMuted)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: model.guardEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(model.guardEnabled ? copy.guardOn : copy.guardOff)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(model.guardEnabled ? Color.bwGreen : Color.bwMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((model.guardEnabled ? Color.bwGreen : Color.bwMuted).opacity(0.10), in: Capsule())
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func statusBanner(_ copy: AppCopy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.bwGreen)
            Text(model.lastInfo)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.bwText.opacity(0.76))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bwGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.bwGreen.opacity(0.16), lineWidth: 1)
        )
    }

    private func deviceSummary(_ copy: AppCopy) -> some View {
        BreathwrkSheet(padding: 0) {
            VStack(spacing: 0) {
                deviceValueRow(
                    symbol: "mic.fill",
                    title: copy.currentInput,
                    value: model.currentInputName.isEmpty ? copy.unknown : model.currentInputName,
                    accent: Color.bwOrange)
                divider
                deviceValueRow(
                    symbol: "speaker.wave.2.fill",
                    title: copy.currentOutput,
                    value: model.currentOutputName.isEmpty ? copy.unknown : model.currentOutputName,
                    accent: Color.bwGreen)
                divider
                deviceValueRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: copy.protectedSwitches,
                    value: "\(model.switchCount)",
                    accent: Color.bwMuted)
            }
        }
    }

    private func moreContent(_ copy: AppCopy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                HStack {
                    Text(copy.settings)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.bwText)
                    Spacer()
                }
                .padding(.horizontal, 2)

                BreathwrkSheet(padding: 0) {
                    VStack(spacing: 0) {
                        toggleRow(copy.launchAtLogin, binding: $model.launchAtLogin)
                        divider
                        toggleRow(copy.blockExternalMics, binding: $model.interceptAllExternal)
                        divider
                        toggleRow(copy.showWindowOnStart, binding: $model.showWindowOnLaunch)
                    }
                }

                BreathwrkSheet(padding: 0) {
                    VStack(spacing: 0) {
                        actionRow(copy.help, symbol: "questionmark.circle") { notice = .help }
                        divider
                        actionRow(copy.privacy, symbol: "hand.raised") { notice = .privacy }
                        divider
                        actionRow(copy.about, value: "\(copy.versionLabel) \(appVersion)", symbol: "info.circle") { notice = .about }
                        divider
                        actionRow(copy.copyDiagnostics, symbol: "doc.on.doc") { model.copyDiagnostics() }
                    }
                }

                Text(copy.explanation)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.bwMuted)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                BreathwrkPrimaryButton(title: copy.quitLyssen) {
                    NSApp.terminate(nil)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func settingsEntry(_ copy: AppCopy) -> some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                page = .more
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.bwOrange)
                    .frame(width: 24)

                Text(copy.moreSettings)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.bwText)

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.bwMuted)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.bwPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.bwLine.opacity(0.80), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func guardControl(_ copy: AppCopy) -> some View {
        BreathwrkSheet(padding: 16) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bwOrangeSoft.opacity(0.78))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.bwOrange)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.guardBluetoothMic)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.bwText)

                    Text(model.guardEnabled ? copy.guardOn : copy.guardOff)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(model.guardEnabled ? Color.bwGreen : Color.bwMuted)
                }

                Spacer(minLength: 12)

                Toggle(isOn: $model.guardEnabled) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(BreathwrkToggleStyle())
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.bwLine.opacity(0.76))
            .frame(height: 1)
            .padding(.leading, 52)
    }

    private var compactDivider: some View {
        Rectangle()
            .fill(Color.bwLine.opacity(0.76))
            .frame(height: 1)
            .padding(.vertical, 7)
    }

    private func toggleRow(_ title: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 10)

            Toggle(isOn: binding) { EmptyView() }
                .labelsHidden()
                .toggleStyle(BreathwrkToggleStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func deviceValueRow(symbol: String, title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                }

            Text(title)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 265, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.bwMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .frame(height: 34)
    }

    private func actionRow(_ title: String, value: String? = nil,
                           symbol: String,
                           isDestructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isDestructive ? Color.bwDanger : Color.bwGreen)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isDestructive ? Color.bwDanger : Color.bwText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Spacer(minLength: 10)

                if let value {
                    Text(value)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.bwMuted)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.bwMuted)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func alertTitle(_ item: InfoNotice) -> String {
        let copy = model.language.copy
        switch item {
        case .help: return copy.helpTitle
        case .privacy: return copy.privacyTitle
        case .about: return copy.aboutTitle
        }
    }

    private func alertMessage(_ item: InfoNotice) -> String {
        let copy = model.language.copy
        switch item {
        case .help:
            return copy.helpMessage
        case .privacy:
            return copy.privacyMessage
        case .about:
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            return "Lyssen \(appVersion) (\(build))\n\n\(copy.explanation)"
        }
    }
}

// MARK: - 应用主体(菜单栏后台 + 浅色窗口)

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = GuardModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = nil
            button.title = "L"
            button.font = NSFont.systemFont(ofSize: 14, weight: .black)
            button.isEnabled = true
            button.toolTip = "Lyssen · 蓝牙麦克风守护"
        }
        rebuildStatusMenu()
        installKeyboardShortcuts()

        model.start()

        if model.showWindowOnLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.openWindow()
            }
        }
    }

    private func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        NSColor.systemOrange.setFill()
        shape.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .black),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSString(string: "L").draw(in: NSRect(x: 0, y: 1.2, width: size.width, height: size.height),
                                   withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开 Lyssen", action: #selector(openWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let guardTitle = model.guardEnabled ? "暂停守护" : "开启守护"
        let guardItem = NSMenuItem(title: guardTitle, action: #selector(toggleGuardFromMenu), keyEquivalent: "")
        guardItem.target = self
        menu.addItem(guardItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Lyssen", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }

            if key == "w" {
                self?.window?.close()
                return nil
            }

            if key == "q" {
                NSApp.terminate(nil)
                return nil
            }

            return event
        }
    }

    @objc private func toggleGuardFromMenu() {
        model.guardEnabled.toggle()
        rebuildStatusMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openWindow() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.collectionBehavior = []
            w.backgroundColor = .clear
            w.isOpaque = false
            w.appearance = NSAppearance(named: .aqua)
            w.title = "Lyssen"
            w.setContentSize(NSSize(width: 560, height: 560))
            w.minSize = NSSize(width: 560, height: 560)
            w.maxSize = NSSize(width: 560, height: 560)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        window?.standardWindowButton(.zoomButton)?.isEnabled = false
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // 关掉窗口不退出,继续后台守护
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import AppKit
import Combine

@main
enum CodexQuotaBarMain {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController()
    }
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = QuotaStore()
    private var cancellable: AnyCancellable?
    private var colorSettingKey: String?
    private var lastRenderState: StatusRenderState?
    private var manuallyDetectedUsesDarkMenuBar: Bool?

    override init() {
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        updateStatusView()

        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusView()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(updateStatusViewForEnvironmentChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func updateStatusViewForEnvironmentChange() {
        updateStatusView()
    }

    private func updateStatusView(force: Bool = false, detectAppearance: Bool = true) {
        let now = Date()
        let renderState = StatusRenderState(
            topBadge: store.snapshot.fiveHourCountdown(at: now),
            bottomBadge: store.snapshot.weeklyCountdown(at: now),
            topValue: store.snapshot.menuFiveHourValue,
            bottomValue: store.snapshot.menuWeeklyValue,
            topIsLow: shouldHighlightLowQuota(store.snapshot.fiveHourRemainingPercent, threshold: store.settings.fiveHourThreshold),
            bottomIsLow: shouldHighlightLowQuota(store.snapshot.weeklyRemainingPercent, threshold: store.settings.weeklyThreshold),
            usesDarkMenuBar: detectAppearance ? (manuallyDetectedUsesDarkMenuBar ?? statusItem.button?.usesDarkMenuBarAppearance ?? false) : (lastRenderState?.usesDarkMenuBar ?? false),
            toolTip: store.snapshot.menuTitle,
            settings: store.settings
        )

        guard force || renderState != lastRenderState else {
            return
        }

        let image = QuotaStatusImageRenderer.render(
            topBadge: renderState.topBadge,
            bottomBadge: renderState.bottomBadge,
            topValue: renderState.topValue,
            bottomValue: renderState.bottomValue,
            topIsLow: renderState.topIsLow,
            bottomIsLow: renderState.bottomIsLow,
            usesDarkMenuBar: renderState.usesDarkMenuBar,
            settings: renderState.settings
        )
        statusItem.button?.image = image
        statusItem.button?.toolTip = renderState.toolTip
        statusItem.length = image.size.width
        lastRenderState = renderState
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusView()

        Task {
            await store.refresh()
        }

        menu.removeAllItems()

        menu.addItem(alignedInfoItem(label: store.snapshot.fiveHourResetLabel, value: store.snapshot.fiveHourResetValue))
        menu.addItem(alignedInfoItem(label: store.snapshot.weeklyResetLabel, value: store.snapshot.weeklyResetValue))
        menu.addItem(alignedInfoItem(label: "时 剩余额度", value: store.snapshot.menuFiveHourValue))
        menu.addItem(alignedInfoItem(label: "周 剩余额度", value: store.snapshot.menuWeeklyValue))

        if let errorMessage = store.snapshot.errorMessage {
            menu.addItem(.separator())
            let error = NSMenuItem(title: "错误 \(errorMessage)", action: nil, keyEquivalent: "")
            error.isEnabled = false
            menu.addItem(error)
        }

        if store.isRefreshing {
            menu.addItem(.separator())
            let refreshing = NSMenuItem(title: "正在刷新...", action: nil, keyEquivalent: "")
            refreshing.isEnabled = false
            menu.addItem(refreshing)
        }

        menu.addItem(.separator())

        menu.addItem(choiceMenu("排列方式", key: "horizontal", choices: [("横向排列", "true"), ("纵向排列", "false")], selected: String(store.settings.horizontal)))
        let fontItem = NSMenuItem()
        let fontSlider = FontSizeSliderView(value: store.settings.fontPoints ?? (store.settings.fontSize == "large" ? 10.8 : (store.settings.fontSize == "medium" ? 9.9 : 9)), maximum: Double(store.settings.horizontal ? NSStatusBar.system.thickness : NSStatusBar.system.thickness / 2))
        fontSlider.onChange = { [weak self] points in
            guard let self else { return }
            self.store.settings.fontPoints = points
            self.updateStatusView(force: true)
        }
        fontItem.view = fontSlider
        menu.addItem(fontItem)
        menu.addItem(choiceMenu("更新速率", key: "refreshSeconds", choices: [("30 秒", "30"), ("1 分钟", "60"), ("2 分钟", "120"), ("5 分钟", "300"), ("10 分钟", "600"), ("15 分钟", "900")], selected: String(store.settings.refreshSeconds)))
        let colors = NSMenuItem(title: "显示颜色", action: nil, keyEquivalent: "")
        let colorsMenu = NSMenu()
        colorsMenu.addItem(colorMenu("标签颜色", key: "labelColor", selected: store.settings.labelColor, allowAuto: true))
        colorsMenu.addItem(colorMenu("百分比颜色", key: "percentageColor", selected: store.settings.percentageColor, allowAuto: true))
        colors.submenu = colorsMenu
        menu.addItem(colors)
        menu.addItem(.separator())
        let alert = NSMenuItem()
        let toggle = LowQuotaSwitchView(isOn: store.lowQuotaAlertEnabled)
        toggle.onToggle = { [weak self, weak menu] enabled in
            guard let self else { return }
            self.store.setLowQuotaAlertEnabled(enabled)
            self.updateStatusView(force: true)
            // Keep the active menu and its views alive while changing visibility.
            menu?.item(withTag: 501)?.isHidden = !enabled
            menu?.item(withTag: 502)?.isHidden = !enabled
        }
        alert.view = toggle
        menu.addItem(alert)
        let fiveHour = alertMenu("时 预警设置", thresholdKey: "fiveHourThreshold", threshold: store.settings.fiveHourThreshold, colorKey: "fiveHourColor", color: store.settings.fiveHourColor)
        fiveHour.tag = 501
        fiveHour.isHidden = !store.lowQuotaAlertEnabled
        menu.addItem(fiveHour)
        let weekly = alertMenu("周 预警设置", thresholdKey: "weeklyThreshold", threshold: store.settings.weeklyThreshold, colorKey: "weeklyColor", color: store.settings.weeklyColor)
        weekly.tag = 502
        weekly.isHidden = !store.lowQuotaAlertEnabled
        menu.addItem(weekly)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func alignedInfoItem(label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuInfoRowView(label: label, value: value)
        return item
    }

    private func shouldHighlightLowQuota(_ remainingPercent: Int?, threshold: Int) -> Bool {
        guard store.lowQuotaAlertEnabled, let remainingPercent else {
            return false
        }

        return remainingPercent <= threshold
    }

    private func choiceMenu(_ title: String, key: String, choices: [(String, String)], selected: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (label, value) in choices {
            let item = NSMenuItem(title: label, action: #selector(changeSetting(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, value]
            item.state = value == selected ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func colorMenu(_ title: String, key: String, selected: String, allowAuto: Bool) -> NSMenuItem {
        var colors = [("红色", "#FF453A"), ("橙色", "#FF9F0A"), ("黄色", "#FFD60A"), ("绿色", "#30D158"), ("蓝色", "#0A84FF"), ("紫色", "#BF5AF2"), ("白色", "#FFFFFF"), ("黑色", "#000000")]
        if allowAuto { colors.insert(("自动适应背景", "auto"), at: 0) }
        let parent = choiceMenu(title, key: key, choices: colors, selected: selected)
        let custom = NSMenuItem(title: "自定义颜色…", action: #selector(chooseCustomColor(_:)), keyEquivalent: "")
        custom.target = self
        custom.representedObject = [key, selected]
        parent.submenu?.addItem(.separator())
        parent.submenu?.addItem(custom)
        return parent
    }

    private func alertMenu(_ title: String, thresholdKey: String, threshold: Int, colorKey: String, color: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let thresholds = choiceMenu("剩余额度 ≤ \(threshold)% 时预警", key: thresholdKey, choices: stride(from: 0, through: 100, by: 5).map { ("\($0)%", String($0)) }, selected: String(threshold))
        let custom = NSMenuItem(title: "自定义比例…", action: #selector(chooseThreshold(_:)), keyEquivalent: "")
        custom.target = self
        custom.representedObject = [thresholdKey, String(threshold)]
        thresholds.submenu?.addItem(custom)
        submenu.addItem(thresholds)
        submenu.addItem(colorMenu("预警颜色", key: colorKey, selected: color, allowAuto: false))
        parent.submenu = submenu
        return parent
    }

    @objc private func toggleAlert() {
        store.toggleLowQuotaAlert()
        updateStatusView(force: true)
    }

    @objc private func chooseThreshold(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String] else { return }
        let alert = NSAlert()
        alert.messageText = "设置低额度比例"
        alert.informativeText = "当剩余额度小于或等于该比例时显示预警颜色（0–100）。"
        let field = NSTextField(string: pair[1])
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            if let value = Int(field.stringValue), (0...100).contains(value) {
                applySetting(pair[0], String(value))
                return
            }
            alert.informativeText = "请输入 0 到 100 之间的整数。"
        }
    }

    @objc private func chooseCustomColor(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String] else { return }
        let panel = NSColorPanel.shared
        panel.orderOut(nil)
        panel.setTarget(nil)
        panel.color = .quotaColor(pair[1], fallback: .systemBlue)
        colorSettingKey = pair[0]
        panel.title = sender.menu?.supermenu?.title ?? "自定义颜色"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ panel: NSColorPanel) {
        guard let key = colorSettingKey else { return }
        applySetting(key, panel.color.quotaHex)
    }

    @objc private func changeSetting(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String] else { return }
        applySetting(pair[0], pair[1])
    }

    private func applySetting(_ key: String, _ value: String) {
        var settings = store.settings
        switch key {
        case "fontSize": if ["small", "medium", "large"].contains(value) { settings.fontSize = value }
        case "horizontal":
            settings.horizontal = value == "true"
            let maximum = Double(settings.horizontal ? NSStatusBar.system.thickness : NSStatusBar.system.thickness / 2)
            if let points = settings.fontPoints { settings.fontPoints = min(max(points, 7), maximum) }
        case "refreshSeconds": if let number = Int(value), number >= 30 { settings.refreshSeconds = number }
        case "labelColor": settings.labelColor = value
        case "percentageColor": settings.percentageColor = value
        case "fiveHourThreshold": if let number = Int(value), (0...100).contains(number) { settings.fiveHourThreshold = number }
        case "weeklyThreshold": if let number = Int(value), (0...100).contains(number) { settings.weeklyThreshold = number }
        case "fiveHourColor": settings.fiveHourColor = value
        case "weeklyColor": settings.weeklyColor = value
        default: return
        }
        store.settings = settings
        updateStatusView(force: true)
    }

    @objc private func refresh() {
        if let button = statusItem.button {
            manuallyDetectedUsesDarkMenuBar =
                MenuBarBackgroundDetector.usesDarkMenuBar(near: button) ??
                WallpaperMenuBarDetector.usesDarkMenuBar(near: button)
            updateStatusView(force: true)
        }

        Task {
            await store.refresh()
            await MainActor.run {
                self.updateStatusView(force: true)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct StatusRenderState: Equatable {
    let topBadge: String
    let bottomBadge: String
    let topValue: String
    let bottomValue: String
    let topIsLow: Bool
    let bottomIsLow: Bool
    let usesDarkMenuBar: Bool
    let toolTip: String
    let settings: DisplaySettings
}

private extension NSStatusBarButton {
    var usesDarkMenuBarAppearance: Bool {
        if let screenBasedResult = MenuBarBackgroundDetector.usesDarkMenuBar(near: self) {
            return screenBasedResult
        }

        return false
    }
}

private enum MenuBarBackgroundDetector {
    static func usesDarkMenuBar(near button: NSStatusBarButton) -> Bool? {
        guard CGPreflightScreenCaptureAccess(),
              let screen = button.window?.screen ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let buttonRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        let localSampleXs: [CGFloat]
        if buttonRect.isEmpty {
            localSampleXs = [
                screen.frame.midX - 80,
                screen.frame.midX - 40,
                screen.frame.midX + 40,
                screen.frame.midX + 80
            ]
        } else {
            localSampleXs = [
                buttonRect.minX - 80,
                buttonRect.minX - 56,
                buttonRect.minX - 32,
                buttonRect.maxX + 32,
                buttonRect.maxX + 56,
                buttonRect.maxX + 80
            ]
        }
        let sampleYs = [
            screen.frame.maxY - 4,
            screen.frame.maxY - (NSStatusBar.system.thickness / 2)
        ]

        let luminanceValues = localSampleXs.flatMap { sampleX in
            sampleYs.compactMap { sampleY in
                sampleLuminance(at: NSPoint(x: sampleX, y: sampleY), screen: screen, displayID: displayID)
            }
        }

        guard luminanceValues.count >= 2 else {
            return nil
        }

        let sorted = luminanceValues.sorted()
        let medianLuminance = sorted[sorted.count / 2]
        return MenuBarContrastHeuristic.usesDarkMenuBar(luminance: medianLuminance, saturation: nil)
    }

    private static func sampleLuminance(at point: NSPoint, screen: NSScreen, displayID: CGDirectDisplayID) -> Double? {
        let scale = screen.backingScaleFactor
        let pixelX = (point.x - screen.frame.minX) * scale
        let pixelY = (point.y - screen.frame.minY) * scale
        let captureRect = CGRect(x: pixelX - 2, y: pixelY - 2, width: 4, height: 4)

        guard let image = CGDisplayCreateImage(displayID, rect: captureRect) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        var values: [Double] = []

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                values.append((0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent))
            }
        }

        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }
}

private enum MenuBarContrastHeuristic {
    static func usesDarkMenuBar(luminance: Double, saturation: Double?) -> Bool {
        if luminance < 0.62 {
            return true
        }

        if let saturation, saturation > 0.25, luminance < 0.72 {
            return true
        }

        return false
    }
}

private enum WallpaperMenuBarDetector {
    static func usesDarkMenuBar(near button: NSStatusBarButton) -> Bool? {
        guard let screen = button.window?.screen ?? NSScreen.main,
              let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: wallpaperURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let samplePoints = menuBarSamplePoints(near: button, on: screen)
        let samples = samplePoints.compactMap { point in
            sampleColor(at: point, screen: screen, bitmap: bitmap)
        }

        guard samples.count >= 2 else {
            return nil
        }

        let sortedLuminance = samples.map(\.luminance).sorted()
        let sortedSaturation = samples.map(\.saturation).sorted()
        let medianLuminance = sortedLuminance[sortedLuminance.count / 2]
        let medianSaturation = sortedSaturation[sortedSaturation.count / 2]
        return MenuBarContrastHeuristic.usesDarkMenuBar(luminance: medianLuminance, saturation: medianSaturation)
    }

    private static func menuBarSamplePoints(near button: NSStatusBarButton, on screen: NSScreen) -> [NSPoint] {
        let buttonRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        let sampleXs: [CGFloat]

        if buttonRect.isEmpty {
            sampleXs = [
                screen.frame.midX - 64,
                screen.frame.midX,
                screen.frame.midX + 64
            ]
        } else {
            sampleXs = [
                buttonRect.minX - 48,
                buttonRect.midX - 18,
                buttonRect.midX,
                buttonRect.midX + 18,
                buttonRect.maxX + 48
            ]
        }

        let sampleYs = [
            screen.frame.maxY - 4,
            screen.frame.maxY - (NSStatusBar.system.thickness / 2)
        ]

        return sampleXs.flatMap { x in
            sampleYs.map { y in
                NSPoint(
                    x: min(max(x, screen.frame.minX + 1), screen.frame.maxX - 1),
                    y: min(max(y, screen.frame.minY + 1), screen.frame.maxY - 1)
                )
            }
        }
    }

    private static func sampleColor(at point: NSPoint, screen: NSScreen, bitmap: NSBitmapImageRep) -> ColorSample? {
        let imageWidth = CGFloat(bitmap.pixelsWide)
        let imageHeight = CGFloat(bitmap.pixelsHigh)
        guard imageWidth > 0, imageHeight > 0 else {
            return nil
        }

        let scale = max(screen.frame.width / imageWidth, screen.frame.height / imageHeight)
        guard scale.isFinite, scale > 0 else {
            return nil
        }

        let displayedWidth = imageWidth * scale
        let displayedHeight = imageHeight * scale
        let displayedOriginX = screen.frame.minX + ((screen.frame.width - displayedWidth) / 2)
        let displayedOriginY = screen.frame.minY + ((screen.frame.height - displayedHeight) / 2)
        let imageX = Int(((point.x - displayedOriginX) / scale).rounded())
        let imageYFromBottom = (point.y - displayedOriginY) / scale
        let imageY = Int((imageHeight - imageYFromBottom).rounded())
        let clampedX = min(max(imageX, 0), bitmap.pixelsWide - 1)
        let clampedY = min(max(imageY, 0), bitmap.pixelsHigh - 1)

        guard let color = bitmap.colorAt(x: clampedX, y: clampedY)?.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent)
        let maxComponent = max(color.redComponent, color.greenComponent, color.blueComponent)
        let minComponent = min(color.redComponent, color.greenComponent, color.blueComponent)
        let saturation = maxComponent > 0 ? (maxComponent - minComponent) / maxComponent : 0
        return ColorSample(luminance: luminance, saturation: saturation)
    }

    private struct ColorSample {
        let luminance: Double
        let saturation: Double
    }
}

private final class FontSizeSliderView: NSView {
    var onChange: ((Double) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider

    init(value: Double, maximum: Double) {
        let upper = max(7, maximum)
        slider = NSSlider(value: min(max(value, 7), upper), minValue: 7, maxValue: upper, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 57))
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 14, y: 32, width: 222, height: 19)
        slider.frame = NSRect(x: 14, y: 7, width: 222, height: 22)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel("字体大小")
        addSubview(label)
        addSubview(slider)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateLabel() {
        label.stringValue = String(format: "字体大小  %.1f  （7–%.1f）", slider.doubleValue, slider.maxValue)
    }

    @objc private func changed() {
        updateLabel()
        onChange?(slider.doubleValue)
    }
}

private final class LowQuotaSwitchView: NSView {
    var onToggle: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "低额度预警")
    private let toggle = PillSwitchControl()

    init(isOn: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 30))

        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .left
        label.frame = NSRect(x: 14, y: 6, width: 110, height: 18)

        toggle.isOn = isOn
        toggle.syncVisualState()
        toggle.onToggle = { [weak self] isOn in
            self?.onToggle?(isOn)
        }
        toggle.frame = NSRect(x: 170, y: 5, width: 46, height: 20)

        addSubview(label)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        toggle.toggleAnimated()
    }
}

private final class MenuInfoRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 28))

        configure(labelField, alignment: .left)
        configure(valueField, alignment: .right)

        labelField.stringValue = label
        valueField.stringValue = value

        labelField.frame = NSRect(x: 14, y: 5, width: 86, height: 18)
        valueField.frame = NSRect(x: 92, y: 5, width: 124, height: 18)

        addSubview(labelField)
        addSubview(valueField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ field: NSTextField, alignment: NSTextAlignment) {
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.alignment = alignment
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false
        field.lineBreakMode = .byClipping
    }
}

private final class PillSwitchControl: NSControl {
    var onToggle: ((Bool) -> Void)?

    var isOn = false

    private var animationProgress: CGFloat = 0
    private var animationTimer: Timer?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
        let trackColor = blendedColor(
            from: NSColor(calibratedWhite: 0.58, alpha: 1),
            to: .systemRed,
            progress: animationProgress
        )
        trackColor.setFill()
        trackPath.fill()

        let knobDiameter = trackRect.height - 4
        let offX = trackRect.minX + 2
        let onX = trackRect.maxX - knobDiameter - 2
        let knobX = offX + (onX - offX) * animationProgress
        let knobRect = NSRect(x: knobX, y: trackRect.minY + 2, width: knobDiameter, height: knobDiameter)
        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor.white.setFill()
        knobPath.fill()
        NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
        knobPath.lineWidth = 0.5
        knobPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        toggleAnimated()
    }

    func toggleAnimated() {
        setOn(!isOn, animated: true)
        onToggle?(isOn)
    }

    func syncVisualState() {
        animationTimer?.invalidate()
        animationProgress = isOn ? 1 : 0
        needsDisplay = true
    }

    private func setOn(_ newValue: Bool, animated: Bool) {
        animationTimer?.invalidate()

        guard animated else {
            isOn = newValue
            animationProgress = newValue ? 1 : 0
            needsDisplay = true
            return
        }

        let start = animationProgress
        let end: CGFloat = newValue ? 1 : 0
        isOn = newValue
        let startTime = Date()
        let duration: TimeInterval = 0.16

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(1, elapsed / duration)
            let eased = 1 - pow(1 - t, 3)
            self.animationProgress = start + (end - start) * eased
            self.needsDisplay = true

            if t >= 1 {
                timer.invalidate()
                self.animationProgress = end
                self.needsDisplay = true
            }
        }
        animationTimer = timer
        RunLoop.current.add(timer, forMode: .eventTracking)
        RunLoop.current.add(timer, forMode: .common)
    }

    private func blendedColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        let fromRGB = from.usingColorSpace(.deviceRGB) ?? from
        let toRGB = to.usingColorSpace(.deviceRGB) ?? to
        let p = max(0, min(1, progress))

        return NSColor(
            calibratedRed: fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * p,
            green: fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * p,
            blue: fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * p,
            alpha: fromRGB.alphaComponent + (toRGB.alphaComponent - fromRGB.alphaComponent) * p
        )
    }
}

private enum QuotaStatusImageRenderer {
    static func render(topBadge: String, bottomBadge: String, topValue: String, bottomValue: String, topIsLow: Bool, bottomIsLow: Bool, usesDarkMenuBar: Bool, settings: DisplaySettings) -> NSImage {
        let height = NSStatusBar.system.thickness
        let legacySize = settings.fontSize == "large" ? 10.8 : (settings.fontSize == "medium" ? 9.9 : 9)
        let points = CGFloat(min(max(settings.fontPoints ?? legacySize, 7), Double(settings.horizontal ? height : height / 2)))
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: points, weight: .regular)
        let badgeFont = NSFont.systemFont(ofSize: points * 0.83, weight: .medium)
        let padding: CGFloat = 5
        let badgeWidth = max(17, ceil(max((topBadge as NSString).size(withAttributes: [.font: badgeFont]).width, (bottomBadge as NSString).size(withAttributes: [.font: badgeFont]).width) + 8))
        let valueWidth = ceil(max((topValue as NSString).size(withAttributes: [.font: valueFont]).width, (bottomValue as NSString).size(withAttributes: [.font: valueFont]).width))
        let rowWidth = padding * 2 + badgeWidth + 4 + valueWidth
        let width = settings.horizontal ? rowWidth * 2 + 4 : rowWidth
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = false
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }
        let palette = Palette(usesDarkMenuBar: usesDarkMenuBar, settings: settings)
        let rowHeight = settings.horizontal ? height : height / 2
        for index in 0..<2 {
            let low = index == 0 ? topIsLow : bottomIsLow
            let color = NSColor.quotaColor(index == 0 ? settings.fiveHourColor : settings.weeklyColor, fallback: .systemRed)
            let x: CGFloat = settings.horizontal ? CGFloat(index) * (rowWidth + 4) : 0
            let y: CGFloat = settings.horizontal ? 0 : CGFloat(index) * rowHeight
            let badgeHeight = min(rowHeight - 2, max(8, points * 0.9))
            let badgeRect = NSRect(x: x + padding, y: y + (rowHeight - badgeHeight) / 2, width: badgeWidth, height: badgeHeight)
            let fill = low ? color : palette.badgeColor
            fill.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2).fill()
            let rgb = fill.usingColorSpace(.sRGB) ?? fill
            let light = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.55
            drawCentered(index == 0 ? topBadge : bottomBadge, font: badgeFont, color: light ? .black : .white, rect: badgeRect, centered: true)
            let rect = NSRect(x: x + padding + badgeWidth + 4, y: y, width: valueWidth + padding, height: rowHeight)
            drawCentered(index == 0 ? topValue : bottomValue, font: valueFont, color: low ? color : palette.valueColor, rect: rect, centered: false)
        }
        return image
    }

    private static func drawCentered(_ text: String, font: NSFont, color: NSColor, rect: NSRect, centered: Bool) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: NSPoint(x: centered ? rect.midX - size.width / 2 : rect.minX, y: rect.midY - size.height / 2))
    }

    private struct Palette {
        var badgeColor: NSColor
        var badgeTextColor: NSColor
        let badgeStrokeColor: NSColor
        var valueColor: NSColor
        let valueStrokeColor: NSColor

        init(usesDarkMenuBar: Bool, settings: DisplaySettings) {
            if usesDarkMenuBar {
                badgeColor = .white
                badgeTextColor = .black
                badgeStrokeColor = NSColor.black.withAlphaComponent(0.35)
                valueColor = .white
                valueStrokeColor = NSColor.black.withAlphaComponent(0.8)
            } else {
                badgeColor = .black
                badgeTextColor = .white
                badgeStrokeColor = NSColor.white.withAlphaComponent(0.55)
                valueColor = .black
                valueStrokeColor = NSColor.white.withAlphaComponent(0.9)
            }
            badgeColor = .quotaColor(settings.labelColor, fallback: badgeColor)
            valueColor = .quotaColor(settings.percentageColor, fallback: valueColor)
            if let rgb = badgeColor.usingColorSpace(.sRGB) {
                let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
                badgeTextColor = luminance > 0.55 ? .black : .white
            }
        }
    }
}

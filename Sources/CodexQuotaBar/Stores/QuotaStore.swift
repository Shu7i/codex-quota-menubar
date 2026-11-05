import AppKit
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    private static let lowQuotaAlertKey = "lowQuotaAlertEnabled"
    private let client = CodexAppServerClient()

    @Published var snapshot: QuotaSnapshot = .empty
    @Published var isRefreshing = false
    @Published var lowQuotaAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lowQuotaAlertEnabled, forKey: Self.lowQuotaAlertKey)
        }
    }

    @Published var settings: DisplaySettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "displaySettings")
            }
            if oldValue.refreshSeconds != settings.refreshSeconds { scheduleRefresh() }
        }
    }
    private var refreshTask: Task<Void, Never>?

    var menuTitle: String {
        snapshot.menuTitle
    }

    var statusLine: String {
        isRefreshing ? "正在刷新..." : snapshot.updatedLine
    }

    init() {
        lowQuotaAlertEnabled = UserDefaults.standard.bool(forKey: Self.lowQuotaAlertKey)

        settings = UserDefaults.standard.data(forKey: "displaySettings")
            .flatMap { try? JSONDecoder().decode(DisplaySettings.self, from: $0) } ?? DisplaySettings()
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(self.settings.refreshSeconds)) }
                catch { return }
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            snapshot = try await client.readQuota()
        } catch {
            // Retain the last successful values and their original timestamp.
            snapshot.errorMessage = "额度查询失败，请检查网络或 Codex 登录状态"
        }
    }

    func toggleLowQuotaAlert() {
        lowQuotaAlertEnabled.toggle()
    }

    func setLowQuotaAlertEnabled(_ isEnabled: Bool) {
        lowQuotaAlertEnabled = isEnabled
    }
}

struct DisplaySettings: Codable, Equatable {
    var fontPoints: Double? = nil
    var fontSize: String? = nil
    var horizontal = false
    var refreshSeconds = 300
    var labelColor = "auto"
    var percentageColor = "auto"
    var fiveHourThreshold = 20
    var weeklyThreshold = 20
    var fiveHourColor = "#FF453A"
    var weeklyColor = "#FF453A"
}

extension NSColor {
    static func quotaColor(_ value: String, fallback: NSColor) -> NSColor {
        guard value.hasPrefix("#"), value.count == 7,
              let rgb = UInt32(value.dropFirst(), radix: 16) else { return fallback }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    var quotaHex: String {
        let rgb = usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

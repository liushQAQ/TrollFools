//
//  AppListModel.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import notify
import Combine
import OrderedCollections
import SwiftUI

final class AppListModel: ObservableObject {
    enum Scope: Int, CaseIterable {
        case all
        case user
        case troll
        case system

        var localizedShortName: String {
            switch self {
            case .all:
                NSLocalizedString("All", comment: "")
            case .user:
                NSLocalizedString("User", comment: "")
            case .troll:
                NSLocalizedString("TrollStore", comment: "")
            case .system:
                NSLocalizedString("System", comment: "")
            }
        }

        var localizedName: String {
            switch self {
            case .all:
                NSLocalizedString("All Applications", comment: "")
            case .user:
                NSLocalizedString("User Applications", comment: "")
            case .troll:
                NSLocalizedString("TrollStore Applications", comment: "")
            case .system:
                NSLocalizedString("Injectable System Applications", comment: "")
            }
        }
    }

    static let isLegacyDevice: Bool = { UIScreen.main.fixedCoordinateSpace.bounds.height <= 736.0 }()
    static let hasTrollStore: Bool = { LSApplicationProxy(forIdentifier: "com.opa334.TrollStore") != nil }()
    private var _allApplications: [App] = []

    let selectorURL: URL?
    var isSelectorMode: Bool { selectorURL != nil }

    @Published var filter = FilterOptions()
    @Published var activeScope: Scope = .all
    @Published var activeScopeApps: OrderedDictionary<String, [App]> = [:]

    @Published var unsupportedCount: Int = 0

    lazy var isFilzaInstalled: Bool = {
        if let filzaURL {
            UIApplication.shared.canOpenURL(filzaURL)
        } else {
            false
        }
    }()
    private let filzaURL = URL(string: "filza://view")

    @Published var isRebuildNeeded: Bool = false

    private let applicationChanged = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var darwinNotifyToken: Int32 = NOTIFY_TOKEN_INVALID

    init(selectorURL: URL? = nil) {
        self.selectorURL = selectorURL
        reload()

        Publishers.CombineLatest(
            $filter,
            $activeScope
        )
        .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
            self?.performFilter()
        }
        .store(in: &cancellables)

        applicationChanged
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        // Uses notify_register_dispatch instead of CFNotificationCenterAddObserver to avoid
        // Unmanaged pointer management. Unlike CFNotificationCenterAddObserver with .coalesce,
        // notify_register_dispatch may deliver queued notifications individually upon app resume,
        // but the .throttle(for: 0.5, ...) on applicationChanged already coalesces rapid bursts.
        notify_register_dispatch("com.apple.LaunchServices.ApplicationsChanged", &darwinNotifyToken, .main) { [weak self] _ in
            self?.applicationChanged.send()
        }
    }

    deinit {
        if darwinNotifyToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(darwinNotifyToken)
        }
    }

    func reload() {
        let allApplications = Self.fetchApplications(&unsupportedCount)
        allApplications.forEach { $0.appList = self }
        _allApplications = allApplications
        performFilter()
        ReinjectManager.shared.checkApps(appList: allApplications)
    }

    func performFilter() {
        var filteredApplications = _allApplications

        if !filter.searchKeyword.isEmpty {
            filteredApplications = filteredApplications.filter {
                $0.name.localizedCaseInsensitiveContains(filter.searchKeyword) || $0.bid.localizedCaseInsensitiveContains(filter.searchKeyword) ||
                    (
                        $0.latinName.localizedCaseInsensitiveContains(
                            filter.searchKeyword
                                .components(separatedBy: .whitespaces).joined()
                        )
                    )
            }
        }

        if filter.showPatchedOnly {
            filteredApplications = filteredApplications.filter { $0.isInjected || $0.hasPersistedAssets }
        }

        switch activeScope {
        case .all:
            activeScopeApps = Self.groupedAppList(filteredApplications)
        case .user:
            activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isUser })
        case .troll:
            activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isFromTroll })
        case .system:
            activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isFromApple })
        }
    }

    private static func fetchApplications(_ unsupportedCount: inout Int) -> [App] {
        let allApps: [App] = LSApplicationWorkspace.default()
            .allApplications()
            .compactMap { proxy in
                guard let id = proxy.applicationIdentifier(),
                      let url = proxy.bundleURL(),
                      let teamID = proxy.teamID(),
                      let appType = proxy.applicationType(),
                      let localizedName = proxy.localizedName()
                else {
                    return nil
                }

                guard !id.hasPrefix("wiki.qaq.") && !id.hasPrefix("com.82flex.") && !id.hasPrefix("ch.xxtou.") else {
                    return nil
                }

                let shortVersionString: String? = proxy.shortVersionString()
                let app = App(
                    bid: id,
                    name: localizedName,
                    type: appType,
                    teamID: teamID,
                    url: url,
                    version: shortVersionString
                )

                if app.isUser && app.isFromApple {
                    return nil
                }

                guard app.isRemovable else {
                    return nil
                }

                return app
            }

        let filteredApps = allApps
            .filter { $0.isSystem || InjectorV3.main.checkIsEligibleAppBundle($0.url) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        unsupportedCount = allApps.count - filteredApps.count

        return filteredApps
    }
}

extension AppListModel {
    func openInFilza(_ url: URL) {
        guard let filzaURL else {
            return
        }

        let fileURL: URL
        if #available(iOS 16, *) {
            fileURL = filzaURL.appending(path: url.path)
        } else {
            fileURL = URL(string: filzaURL.absoluteString + (url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!
        }

        UIApplication.shared.open(fileURL)
    }

    func rebuildIconCache() {
        // Sadly, we can't call `trollstorehelper` directly because only TrollStore can launch it without error.
        DispatchQueue.global(qos: .userInitiated).async {
            LSApplicationWorkspace.default().openApplication(withBundleID: "com.opa334.TrollStore")
        }
    }
}

extension AppListModel {
    static let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#"
    private static let allowedCharacterSet = CharacterSet(charactersIn: allowedCharacters)

    private static func groupedAppList(_ apps: [App]) -> OrderedDictionary<String, [App]> {
        var groupedApps = OrderedDictionary<String, [App]>()

        for app in apps {
            var key = app.name
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .applyingTransform(.stripCombiningMarks, reverse: false)?
                .applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .prefix(1).uppercased() ?? "#"

            if let scalar = UnicodeScalar(key) {
                if !allowedCharacterSet.contains(scalar) {
                    key = "#"
                }
            } else {
                key = "#"
            }

            if groupedApps[key] == nil {
                groupedApps[key] = []
            }

            groupedApps[key]?.append(app)
        }

        groupedApps.sort { app1, app2 in
            if let c1 = app1.key.first,
               let c2 = app2.key.first,
               let idx1 = allowedCharacters.firstIndex(of: c1),
               let idx2 = allowedCharacters.firstIndex(of: c2)
            {
                return idx1 < idx2
            }
            return app1.key < app2.key
        }

        return groupedApps
    }
}

// MARK: - Reinject Manager (State-Preserving Auto-Restore)

struct SavedPluginState: Codable, Equatable {
    let fileName: String
    var isEnabled: Bool

    init(fileName: String, isEnabled: Bool) {
        self.fileName = fileName
        self.isEnabled = isEnabled
    }
}

struct SavedAppState: Codable {
    let bid: String
    var appVersion: String
    var plugins: [SavedPluginState]
    var lastUpdated: Date

    init(bid: String, appVersion: String, plugins: [SavedPluginState], lastUpdated: Date = Date()) {
        self.bid = bid
        self.appVersion = appVersion
        self.plugins = plugins
        self.lastUpdated = lastUpdated
    }
}

final class ReinjectManager: ObservableObject {
    static let shared = ReinjectManager()

    static let registryDirectoryURL: URL = {
        let url = URL(fileURLWithPath: "/var/mobile/Library/TrollFools/StateRegistry", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @Published var appsNeedingRestore: [App] = []
    @Published var isRestoring: Bool = false
    @Published var statusMessage: String = ""

    private let fileManager = FileManager.default

    private init() {}

    private func registryFileURL(for bid: String) -> URL {
        Self.registryDirectoryURL.appendingPathComponent("\(bid).json")
    }

    func loadState(for bid: String) -> SavedAppState? {
        let url = registryFileURL(for: bid)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SavedAppState.self, from: data) else {
            return nil
        }
        return state
    }

    /// 拍摄快照：在任何注入/开关/移除操作后调用，记录哪些插件开启，哪些插件关闭
    func snapshot(_ app: App) {
        let bid = app.bid
        let appVersion = app.version ?? ""

        let activeURLs = InjectorV3.main.injectedAssetURLsInBundle(app.url)
        let activeNames = Set(activeURLs.map { $0.lastPathComponent })

        let persistedURLs = InjectorV3.main.persistedAssetURLs(bid: bid)
        let disabledNames = Set(persistedURLs.map { $0.lastPathComponent }).subtracting(activeNames)

        var pluginStates: [SavedPluginState] = []
        for name in activeNames.sorted() {
            pluginStates.append(SavedPluginState(fileName: name, isEnabled: true))
        }
        for name in disabledNames.sorted() {
            pluginStates.append(SavedPluginState(fileName: name, isEnabled: false))
        }

        let fileURL = registryFileURL(for: bid)
        if pluginStates.isEmpty {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        let state = SavedAppState(
            bid: bid,
            appVersion: appVersion,
            plugins: pluginStates,
            lastUpdated: Date()
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 检测是否有被 App Store 覆盖导致插件丢失的 App
    func checkApps(appList: [App]) {
        let isDetectionEnabled = UserDefaults.standard.object(forKey: "EnableAppUpdateDetection") as? Bool ?? true
        guard isDetectionEnabled else {
            DispatchQueue.main.async { self.appsNeedingRestore = [] }
            return
        }

        var needingRestore: [App] = []

        for app in appList {
            guard let savedState = loadState(for: app.bid) else { continue }

            let expectedActiveNames = Set(savedState.plugins.filter { $0.isEnabled }.map { $0.fileName })
            if expectedActiveNames.isEmpty { continue }

            let currentActiveURLs = InjectorV3.main.injectedAssetURLsInBundle(app.url)
            let currentActiveNames = Set(currentActiveURLs.map { $0.lastPathComponent })

            let missingExpected = !expectedActiveNames.isSubset(of: currentActiveNames)
            let versionChanged = (app.version ?? "") != savedState.appVersion && !savedState.appVersion.isEmpty

            if missingExpected || versionChanged {
                let persistedURLs = InjectorV3.main.persistedAssetURLs(bid: app.bid)
                let persistedNames = Set(persistedURLs.map { $0.lastPathComponent })
                if !expectedActiveNames.intersection(persistedNames).isEmpty {
                    needingRestore.append(app)
                }
            }
        }

        DispatchQueue.main.async {
            self.appsNeedingRestore = needingRestore
            let autoRestore = UserDefaults.standard.bool(forKey: "AutoRestoreInjectedOnLaunch")
            if autoRestore && !needingRestore.isEmpty && !self.isRestoring {
                self.restoreAll()
            }
        }
    }

    /// 一键恢复所有受影响的应用（严格保持开启/关闭状态）
    func restoreAll(completion: (() -> Void)? = nil) {
        guard !appsNeedingRestore.isEmpty, !isRestoring else { return }
        isRestoring = true
        let targets = appsNeedingRestore

        DispatchQueue.global(qos: .userInitiated).async {
            for (index, app) in targets.enumerated() {
                DispatchQueue.main.async {
                    self.statusMessage = String(format: NSLocalizedString("Restoring %d/%d: %@", comment: ""), index + 1, targets.count, app.name)
                }
                self.restoreApp(app)
            }

            DispatchQueue.main.async {
                self.isRestoring = false
                self.statusMessage = NSLocalizedString("Restore Completed", comment: "")
                self.appsNeedingRestore = []
                completion?()
            }
        }
    }

    /// 单个应用精准恢复
    func restoreApp(_ app: App) {
        guard let savedState = loadState(for: app.bid) else { return }

        guard let injector = try? InjectorV3(app.url) else { return }
        if injector.appID.isEmpty { injector.appID = app.bid }
        if injector.teamID.isEmpty { injector.teamID = app.teamID }

        // 仅挑选之前为【开启】状态的插件
        let enabledNames = Set(savedState.plugins.filter { $0.isEnabled }.map { $0.fileName })
        let persistedURLs = injector.persistedAssetURLs(bid: app.bid)
        let urlsToInject = persistedURLs.filter { enabledNames.contains($0.lastPathComponent) }

        // 注入到新二进制
        if !urlsToInject.isEmpty {
            try? injector.inject(urlsToInject, shouldPersist: false)
        }

        // 之前为【关闭】状态的插件绝不注入，保持静默！

        DispatchQueue.main.async {
            app.reload()
            self.snapshot(app)
        }
    }
}


//
//  CheckUpdateManager.swift
//  TRApp
//
//  Created by 82Flex on 2024/11/9.
//

import Combine
import DpkgVersion
import Foundation
import UIKit

private let TTAAGG = "CheckUpdateManager"

/// 统一叫做 CheckUpdate
final class CheckUpdateManager {
    // MARK: - Singleton

    static let shared = CheckUpdateManager()

    // MARK: - Data Models

    struct LatestVersion: Codable {
        let tagName: String // "4.4.2-262"
        let tipaAssetURLString: String
        let versionString: String // "4.4.2"
        let buildVersionString: String // "262"
        let changelog: String?
        let releaseURLString: String?
    }

    // MARK: - Published Properties

    let latestVersionSubject = CurrentValueSubject<LatestVersion?, Never>(nil)

    // MARK: - Private Storage Properties

    @CodableStorage(key: "ApplicationLastCheckUpdateAt", defaultValue: Date(timeIntervalSince1970: 0))
    private var lastCheckUpdateAt: Date {
        didSet {
            if lastCheckUpdateAt != oldValue {
                print("\(TTAAGG) : Check update at: \(lastCheckUpdateAt)")
            }
        }
    }

    @CodableStorage(key: "ApplicationLastCheckUpdateResult", defaultValue: nil)
    private var lastCheckUpdateResult: LatestVersion? {
        didSet {
            latestVersionSubject.send(lastCheckUpdateResult)
            if let lastCheckUpdateResult {
                print("\(TTAAGG) : Latest version: \(String(describing: lastCheckUpdateResult))")
            }
        }
    }

    @CodableStorage(key: "ApplicationBlockUpgradeAlertUntil", defaultValue: Date(timeIntervalSince1970: 0))
    private var blockCheckUpdateAlertUntil: Date {
        didSet {
            if blockCheckUpdateAlertUntil != oldValue {
                print("\(TTAAGG) : Block check update alert until: \(blockCheckUpdateAlertUntil)")
            }
        }
    }

    // MARK: - Public Properties

    /// 是否应该弹出更新提醒
    var shouldPopCheckUpdateAlert: Bool {
        blockCheckUpdateAlertUntil < Date()
    }

    /// 是否有新版本可用
    var isNewVersionAvailable: Bool {
        guard let upstreamVersionCompareKey else {
            return false
        }
        return Version.compare(upstreamVersionCompareKey, currentVersionCompareKey) > 0
    }

    // MARK: - 国内免代理极速镜像端点矩阵

    private static let updateEndpoints: [String] = [
        "https://ghfast.top/https://raw.githubusercontent.com/liushQAQ/TrollFools/main/releases/latest.json",
        "https://gh-proxy.com/https://raw.githubusercontent.com/liushQAQ/TrollFools/main/releases/latest.json",
        "https://raw.gitmirror.com/liushQAQ/TrollFools/main/releases/latest.json",
        "https://raw.githubusercontent.com/liushQAQ/TrollFools/main/releases/latest.json",
        "https://ghfast.top/https://api.github.com/repos/liushQAQ/TrollFools/releases",
        "https://gh-proxy.com/https://api.github.com/repos/liushQAQ/TrollFools/releases",
        "https://api.github.com/repos/liushQAQ/TrollFools/releases"
    ]

    // MARK: - Initialization

    private init() {
        latestVersionSubject.send(lastCheckUpdateResult)
        let trollStore = checkTrollStoreAvailability()
        print("\(TTAAGG) : TrollStore availability: \(trollStore)")
    }

    // MARK: - Public Methods

    /// 延迟更新提醒一周
    func delayCheckUpdateAlert() {
        blockCheckUpdateAlertUntil = Date(timeIntervalSinceNow: Constants.updateManagerAlertDelayDuration)
    }

    /// 兼容旧版调用
    func checkUpdateIfNeeded(completion: ((LatestVersion?, Error?) -> Void)? = nil) {
        checkUpdate(manual: false, completion: completion)
    }

    /// 统一检查更新入口（支持 manual 手动强制触发，带完整 UI 反馈与国内加速）
    func checkUpdate(manual: Bool = false, completion: ((LatestVersion?, Error?) -> Void)? = nil) {
        if !manual {
            guard isCheckUpdateNeeded else {
                print("\(TTAAGG) : Auto check update skipped (within 2h cooldown).")
                if isNewVersionAvailable {
                    completion?(lastCheckUpdateResult, nil)
                } else {
                    completion?(nil, nil)
                }
                return
            }
        }

        lastCheckUpdateAt = Date()

        var loadingAlert: UIAlertController?
        if manual, let topVC = Self.topViewController {
            let alert = UIAlertController(title: "正在检查更新", message: "正在连接国内加速节点检查最新构建…", preferredStyle: .alert)
            topVC.present(alert, animated: true)
            loadingAlert = alert
        }

        performMultiMirrorUpdateCheck { [weak self] latestVersion, error in
            DispatchQueue.main.async {
                let finishHandler = {
                    guard let self else { return }
                    if let latestVersion {
                        self.lastCheckUpdateResult = latestVersion
                        let remoteCompareKey = [latestVersion.versionString, latestVersion.buildVersionString].joined(separator: "-")
                        let hasNewVersion = Version.compare(remoteCompareKey, self.currentVersionCompareKey) > 0

                        if hasNewVersion {
                            self.presentUpgradePrompt(latestVersion)
                            completion?(latestVersion, nil)
                        } else if manual {
                            self.presentUpToDateAlert(latestVersion)
                            completion?(nil, nil)
                        } else {
                            completion?(nil, nil)
                        }
                    } else if manual {
                        let errMsg = error?.localizedDescription ?? "所有更新节点均未能响应，请检查设备网络连接。"
                        let alert = UIAlertController(title: "检查更新失败", message: "无法获取仓库最新版本：\(errMsg)", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        Self.topViewController?.present(alert, animated: true)
                        completion?(nil, error)
                    } else {
                        completion?(nil, error)
                    }
                }

                if let alert = loadingAlert {
                    alert.dismiss(animated: true, completion: finishHandler)
                } else {
                    finishHandler()
                }
            }
        }
    }

    /// 弹出已是最新版本的通知
    private func presentUpToDateAlert(_ info: LatestVersion) {
        guard let topVC = Self.topViewController else { return }
        let alert = UIAlertController(
            title: "✅ 当前已是最新版本",
            message: "当前版本：v\(Constants.gAppVersion) (Build \(Constants.gAppBuildVersion))\n仓库最新：v\(info.versionString) (Build \(info.buildVersionString))\n\n您使用的已经是最新增强版，无需重复更新。",
            preferredStyle: .alert
        )

        if !info.tipaAssetURLString.isEmpty {
            alert.addAction(UIAlertAction(title: "🚀 重新下载并用巨魔安装 (免代理加速)", style: .default) { [weak self] _ in
                let filename = "TrollFools_\(info.tagName).tipa"
                self?.downloadAndInstallTIPA(remoteURLString: info.tipaAssetURLString, filename: filename)
            })
        }

        alert.addAction(UIAlertAction(title: "好", style: .cancel))
        topVC.present(alert, animated: true)
    }

    /// 弹出升级提示对话框
    func presentUpgradePrompt(_ info: LatestVersion) {
        guard let topVC = Self.topViewController else { return }
        let tagName = info.tagName
        let filename = "TrollFools_\(tagName).tipa"
        let notes = info.changelog ?? "包含最新的巨魔防 301 报错修复、免代理极速下载通道与稳定性升级。"

        let alert = UIAlertController(
            title: "🎉 发现新版本 v\(tagName)",
            message: "当前版本：v\(Constants.gAppVersion) (Build \(Constants.gAppBuildVersion))\n\n【更新说明】\n\(notes)\n\n推荐点击下方按钮，App 将通过国内免代理通道极速下载并自动调起巨魔安装（彻底避免 301 报错）。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "🚀 极速下载并用巨魔安装 (推荐·零报错)", style: .default) { [weak self] _ in
            self?.downloadAndInstallTIPA(remoteURLString: info.tipaAssetURLString, filename: filename)
        })

        alert.addAction(UIAlertAction(title: "⚡ 巨魔一键直连安装", style: .default) { [weak self] _ in
            let fallbackURL = URL(string: info.releaseURLString ?? info.tipaAssetURLString) ?? URL(string: "https://github.com/liushQAQ/TrollFools/releases")!
            self?.installViaTrollStore(remoteURLString: info.tipaAssetURLString, fallbackURL: fallbackURL, filename: filename)
        })

        if let rel = info.releaseURLString, let relURL = URL(string: rel) {
            alert.addAction(UIAlertAction(title: "🌐 打开仓库页面", style: .default) { _ in
                UIApplication.shared.open(relURL)
            })
        }

        alert.addAction(UIAlertAction(title: "稍后提醒", style: .cancel))
        topVC.present(alert, animated: true)
    }

    /// 执行升级（公共调用）
    func executeUpgrade() {
        if let result = lastCheckUpdateResult {
            presentUpgradePrompt(result)
        } else {
            checkUpdate(manual: true)
        }
    }

    // MARK: - 国内免代理极速下载与巨魔本地安装 (彻底根治 301 报错)

    static func mirrorCandidates(for rawURL: String) -> [String] {
        guard !rawURL.isEmpty else { return [] }
        if rawURL.contains("ghfast.top") || rawURL.contains("gh-proxy.com") {
            return [rawURL]
        }
        return [
            "https://ghfast.top/\(rawURL)",
            "https://gh-proxy.com/\(rawURL)",
            rawURL
        ]
    }

    private static var topViewController: UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              var top = window.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    func installViaTrollStore(remoteURLString: String, fallbackURL: URL, filename: String) {
        let candidates = Self.mirrorCandidates(for: remoteURLString)
        let acceleratedURL = candidates.first(where: { $0.contains("ghfast.top") || $0.contains("gh-proxy.com") }) ?? candidates.first ?? remoteURLString

        guard let reqURL = URL(string: acceleratedURL) else {
            downloadAndInstallTIPA(remoteURLString: remoteURLString, filename: filename)
            return
        }

        var req = URLRequest(url: reqURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        req.httpMethod = "HEAD"

        URLSession.shared.dataTask(with: req) { [weak self] _, resp, error in
            let finalTarget: String = {
                if let http = resp as? HTTPURLResponse, let finalURL = http.url?.absoluteString, !finalURL.isEmpty {
                    return finalURL
                }
                return acceleratedURL
            }()

            DispatchQueue.main.async {
                guard let encoded = finalTarget.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    self?.downloadAndInstallTIPA(remoteURLString: remoteURLString, filename: filename)
                    return
                }

                let schemes = [
                    "apple-magnifier://install?url=\(encoded)",
                    "trollstore://install?url=\(encoded)"
                ]

                var didOpen = false
                let group = DispatchGroup()
                for s in schemes {
                    if let u = URL(string: s) {
                        group.enter()
                        UIApplication.shared.open(u, options: [:]) { success in
                            if success { didOpen = true }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    if !didOpen {
                        self?.downloadAndInstallTIPA(remoteURLString: remoteURLString, filename: filename)
                    }
                }
            }
        }.resume()
    }

    private func downloadAndInstallTIPA(remoteURLString: String, filename: String) {
        let candidates = Self.mirrorCandidates(for: remoteURLString)
        guard !candidates.isEmpty else { return }
        guard let topVC = Self.topViewController else { return }

        let progressAlert = UIAlertController(title: "正在加速下载最新包", message: "正在通过国内镜像下载 \(filename)…\n进度：0%", preferredStyle: .alert)
        topVC.present(progressAlert, animated: true)

        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destURL)

        func tryDownload(index: Int) {
            guard index < candidates.count, let url = URL(string: candidates[index]) else {
                DispatchQueue.main.async {
                    progressAlert.dismiss(animated: true) {
                        let alert = UIAlertController(title: "下载失败", message: "所有国内加速镜像节点均无法下载，请稍后重试。", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "好", style: .default))
                        Self.topViewController?.present(alert, animated: true)
                    }
                }
                return
            }

            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, resp, error in
                observation?.invalidate()
                let statusOK = (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
                if error != nil || !statusOK || localURL == nil {
                    tryDownload(index: index + 1)
                    return
                }
                guard let localURL = localURL else { return }
                do {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.moveItem(at: localURL, to: destURL)
                    DispatchQueue.main.async {
                        progressAlert.dismiss(animated: true) {
                            self?.openDownloadedTIPA(fileURL: destURL)
                        }
                    }
                } catch {
                    tryDownload(index: index + 1)
                }
            }

            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async {
                    let pct = Int(progress.fractionCompleted * 100)
                    progressAlert.message = "正在通过国内镜像 (节点 \(index + 1)) 下载 \(filename)…\n进度：\(pct)%"
                }
            }
            task.resume()
        }

        tryDownload(index: 0)
    }

    private func openDownloadedTIPA(fileURL: URL) {
        if let encoded = fileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let tsURL = URL(string: "apple-magnifier://install?url=\(encoded)") {
            UIApplication.shared.open(tsURL, options: [:]) { [weak self] success in
                if !success {
                    self?.presentShareForFile(fileURL)
                }
            }
        } else {
            presentShareForFile(fileURL)
        }
    }

    private func presentShareForFile(_ fileURL: URL) {
        guard let topVC = Self.topViewController else { return }
        let act = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        act.popoverPresentationController?.sourceView = topVC.view
        topVC.present(act, animated: true)
    }

    // MARK: - Private Properties

    /// 是否需要自动检查更新
    private var isCheckUpdateNeeded: Bool {
        let updateCheckIntervalSinceNow = Date().timeIntervalSince(lastCheckUpdateAt)

        if abs(updateCheckIntervalSinceNow) > Constants.updateManagerCheckInterval {
            return true
        }

        if abs(updateCheckIntervalSinceNow) > Constants.updateManagerRetryInterval, lastCheckUpdateResult == nil {
            return true
        }

        return false
    }

    /// 上游版本比较键
    private var upstreamVersionCompareKey: String? {
        guard let lastCheckUpdateResult else {
            return nil
        }
        return [lastCheckUpdateResult.versionString, lastCheckUpdateResult.buildVersionString].joined(separator: "-")
    }

    /// 当前版本比较键
    private var currentVersionCompareKey: String {
        [Constants.gAppVersion, Constants.gAppBuildVersion].joined(separator: "-")
    }

    // MARK: - 多镜像并发加速探测更新

    private func performMultiMirrorUpdateCheck(completion: @escaping (LatestVersion?, Error?) -> Void) {
        let endpoints = Self.updateEndpoints
        let lock = NSLock()
        var bestVersion: LatestVersion?
        var completedCount = 0
        var hasFinished = false
        var lastError: Error?
        let total = endpoints.count
        let ts = Int(Date().timeIntervalSince1970)

        func finishWithResult(_ result: LatestVersion?) {
            lock.lock()
            if hasFinished {
                lock.unlock()
                return
            }
            hasFinished = true
            lock.unlock()
            completion(result, lastError)
        }

        for endpoint in endpoints {
            let sep = endpoint.contains("?") ? "&" : "?"
            guard let url = URL(string: "\(endpoint)\(sep)_t=\(ts)") else {
                lock.lock()
                completedCount += 1
                if completedCount >= total && !hasFinished {
                    lock.unlock()
                    finishWithResult(bestVersion)
                } else {
                    lock.unlock()
                }
                continue
            }

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            URLSession.shared.dataTask(with: request) { data, resp, error in
                var parsed: LatestVersion?
                if error == nil,
                   let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let data = data {
                    parsed = Self.parseUpdateData(data)
                }

                lock.lock()
                completedCount += 1
                if let err = error { lastError = err }

                if let found = parsed {
                    let foundKey = [found.versionString, found.buildVersionString].joined(separator: "-")
                    let bestKey = bestVersion.map { [$0.versionString, $0.buildVersionString].joined(separator: "-") } ?? "0.0.0-0"
                    if Version.compare(foundKey, bestKey) > 0 {
                        bestVersion = found
                    }

                    // 如果检测到高于当前版本的最新版本，立即响应返回
                    let currentKey = [Constants.gAppVersion, Constants.gAppBuildVersion].joined(separator: "-")
                    if Version.compare(foundKey, currentKey) > 0 {
                        lock.unlock()
                        finishWithResult(found)
                        return
                    }
                }

                if completedCount >= total {
                    lock.unlock()
                    finishWithResult(bestVersion)
                } else {
                    lock.unlock()
                }
            }.resume()
        }
    }

    /// 支持解析最新 release.json 单字典或 GitHub Releases 列表数组
    private static func parseUpdateData(_ data: Data) -> LatestVersion? {
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // latest.json 格式
            var tag = jsonDict["tag_name"] as? String ?? jsonDict["version"] as? String ?? ""
            if tag.hasPrefix("v") { tag.removeFirst() }
            let tipaURL = jsonDict["tipa_url"] as? String ?? jsonDict["public_tipa_url"] as? String ?? ""
            let ver = jsonDict["version"] as? String ?? "4.4.2"
            let build = jsonDict["build"].map { "\($0)" } ?? "262"
            let notes = jsonDict["changelog"] as? String ?? jsonDict["title"] as? String
            let relURL = jsonDict["release_url"] as? String
            if !tipaURL.isEmpty {
                return LatestVersion(
                    tagName: tag.isEmpty ? "\(ver)-\(build)" : tag,
                    tipaAssetURLString: tipaURL,
                    versionString: ver,
                    buildVersionString: build,
                    changelog: notes,
                    releaseURLString: relURL
                )
            }
        }

        if let versionList = try? JSONSerialization.jsonObject(with: data) as? [[String: AnyHashable]] {
            // GitHub API Releases 数组格式
            var latestTagName = "0"
            var latestPackageURLString: String?
            var latestNotes: String?
            var latestRelURL: String?

            for versionDict in versionList {
                if let prerelease = versionDict["prerelease"] as? Bool, prerelease {
                    continue
                }

                guard var tagName = versionDict["tag_name"] as? String else {
                    continue
                }

                if tagName.hasPrefix("v") {
                    tagName.removeFirst()
                }

                guard Version.compare(tagName, latestTagName) > 0 else {
                    continue
                }

                guard let assetList = versionDict["assets"] as? [[String: Any]] else {
                    continue
                }

                var foundTIPA: String?
                for asset in assetList {
                    if let name = asset["name"] as? String, name.hasSuffix("tipa"),
                       let url = asset["browser_download_url"] as? String {
                        foundTIPA = url
                        break
                    }
                }

                if let pkgURL = foundTIPA {
                    latestTagName = tagName
                    latestPackageURLString = pkgURL
                    latestNotes = versionDict["body"] as? String
                    latestRelURL = versionDict["html_url"] as? String
                }
            }

            if let pkgURL = latestPackageURLString {
                var components = latestTagName.components(separatedBy: "-")
                if components.count == 1 { components.append("1") }
                let verStr = components.first ?? "4.4.2"
                let bldStr = components.last ?? "262"
                return LatestVersion(
                    tagName: latestTagName,
                    tipaAssetURLString: pkgURL,
                    versionString: verStr,
                    buildVersionString: bldStr,
                    changelog: latestNotes,
                    releaseURLString: latestRelURL
                )
            }
        }

        return nil
    }

    /// 检查 TrollStore 可用性
    private func checkTrollStoreAvailability() -> Bool {
        let applicationProxyForIdentifierSelector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard let applicationProxyCls = NSClassFromString("LSApplicationProxy"),
              applicationProxyCls.responds(to: applicationProxyForIdentifierSelector)
        else {
            return false
        }

        let method = class_getClassMethod(applicationProxyCls, applicationProxyForIdentifierSelector)
        guard let method else {
            return false
        }

        typealias ApplicationProxyFunction = @convention(c) (AnyClass, Selector, NSString) -> Unmanaged<AnyObject>?
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: ApplicationProxyFunction.self)

        guard let applicationProxy = function(
            applicationProxyCls,
            applicationProxyForIdentifierSelector,
            Constants.trollStoreIdentifier as NSString
        )?.takeUnretainedValue() as? NSObject else {
            return false
        }

        guard let bundleURL = applicationProxy.value(forKey: "bundleURL") as? URL,
              let appBundle = Bundle(url: bundleURL),
              let urlTypes = appBundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              !urlTypes.isEmpty
        else {
            return false
        }

        return true
    }
}

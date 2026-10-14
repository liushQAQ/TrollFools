# Changelog

## 4.4.2 Build 263 (2026-10-14)

彻底修复检查更新按钮无反应问题与国内多镜像自动测速容灾：
- **解除静默时间锁**：修复用户在设置中点击【Check for Updates】被 2 小时静默锁拦截的问题，手动点击立即发起强制检查。
- **全流程交互弹窗**：新增点击即时弹窗反馈，支持清晰展示「正在检查更新」、「发现新版本及更新日志」、「已是最新版本无需更新」以及具体的网络故障提示。
- **国内免代理极速双通道**：支持 `latest.json` 与 Releases 列表多节点并发测速，彻底免除直连 `api.github.com` 的国内网络阻断与 IP 限流。
- **巨魔 301 报错彻底根治**：App 内极速下载后直调巨魔本地秒装，零网络重定向报错。

------

## 4.4.2 Build 262 (2026-10-14)

彻底根治巨魔 (TrollStore) 更新报错 301 与国内极速下载升级体验优化：
- **App 内免代理极速下载通道**：新增 App 内部原生高速免代理下载通道（自动智能跟随任何 301/302 重定向），实时展示下载进度百分比。
- **直调巨魔秒级本地安装**：下载完成后直接通过本地安全通道调起 TrollStore 瞬间秒装，100% 彻底消除 TrollStore 网络模块遇到的 HTTP 301 / 302 重定向报错。
- **直连直链预解析防御**：对直接调起巨魔 URL 的场景增加 HEAD 预解析机制，解析出最终 200 状态直链再传递，双重加固杜绝 301。
- **更新源直连与多节点容灾**：自动匹配国内高速镜像节点，确保在无外网代理环境下秒级检测与更新。

------

## 4.4.2 Build 261 (2026-10-14)

界面交互与便利性重大优化：
- 首页左上角新增全局 ⚙️ 设置按钮：点开即是“自动恢复注入开关”、“更新检测开关”及全局状态面板，再也不用逐个点进二级菜单寻找。
- 首页应用列表增加长按快捷菜单：长按任意 App 直接弹出“管理插件”和“恢复插件”选项。
- 应用详情页顶部增加更新提示横幅：检测到单应用被 App Store 覆盖时，在详情页顶部直接提供“恢复上次状态”一键按钮。

------

## 4.4.2 Build 260 (2026-10-13)

增强版更新：新增 App Store 更新检测与严格状态保留恢复注入功能。

### 新增
- 状态记录：每次修改插件开关状态时自动持久化快照，精准记录每个 dylib 是开启还是关闭。
- 覆盖检测：自动检测 App 是否被 App Store 覆盖更新导致 Mach-O 加载链丢失。
- 严格恢复注入：首页顶部提示一键恢复，严格按上次记录的开启/关闭状态恢复注入，绝不误开启被停用的插件。
- 自定义开关：高级选项中提供“启动时自动恢复注入”等独立开关。
- 自定义更新源：支持联网检查并自动获取自定义仓库的新版本。

------

## 4.3 Build 253 (2026-04-23)

修复与 MachOKit 有关的一处断言崩溃。

------

## 4.3 Build 253 (2026-04-23) [EN]

Fixed an assertion crash related to MachOKit.

------

## 4.3 Build 246 (2026-04-16)

修复二次注入时可能误选已注入动态库作为目标 Mach-O 的问题。

### 修复

- 注入目标选取：修复追加注入时，上次注入的动态库可能被误选为注入目标的问题。  
  新增三层防御：从注入前备份读取原始 Load Commands 以还原真实依赖链；枚举阶段跳过 `.troll-fools.bak` 备份文件；通过备份差分精确识别并排除已注入的动态库。

------

## 4.3 Build 246 (2026-04-16) [EN]

Fixed an issue where re-injection could incorrectly select a previously-injected dylib as the target Mach-O.

### Fixed

- Target selection: Fixed re-injection potentially picking a previously-injected dylib as the injection target.  
  Added three-layer defense: read original load commands from pre-injection backup to restore the true dependency chain; skip `.troll-fools.bak` backup files during enumeration; use backup-diff to precisely identify and exclude previously-injected dylibs.

------

## 4.3 (2026-04-13)

本次版本聚焦于“动态加载框架兼容性”和“页面说明可理解性”，并包含插件管理流程调整与资源清理。

### 修复

- 注入兼容性：修复部分 Unity/运行时 `dlopen` 场景下无法命中可注入目标的问题。  
  当主程序静态链接交集为空时，改为回退扫描 `Frameworks/` 中可用 Mach-O（含一级目录下 `.dylib`）。
- 插件管理：调整“移除插件”流程，区分已启用与已禁用插件：  
  已启用插件执行卸载；已禁用插件执行标记清理，降低批量处理风险。

### 新增

- 高级选项：新增“启用兼容模式回退”开关（默认开启），可控制是否在无静态链接命中时启用回退候选。
- 结果页提示：当本次注入通过兼容模式完成时，在“已完成”下方显示额外提示。

### 优化

- 候选筛选：回退候选新增过滤，排除 `libswift*` 与已忽略注入相关动态库/框架，并统一大小写处理。
- 诊断日志：增强 Mach-O 扫描日志，输出候选数量、文件大小、加密/不可读统计与最终选择结果，便于定位“无可用目标”问题。
- 设置说明：优化高级选项页面结构与说明文案，减少非技术用户理解成本。
- 广告与资源：移除内置广告位 `Letterpress` 及相关本地化词条/图标资源；更新营销图素材。

### 本地化

- 更新 `en/zh-Hans/it/vi` 词条，补充兼容模式与设置说明相关文案，并清理移除条目对应文案。

------

## 4.3 (2026-04-13) [EN]

This release focuses on dynamic-framework injection compatibility and clearer user guidance, plus plugin-management flow adjustments and resource cleanup.

### Fixed

- Injection compatibility: Fixed cases (notably Unity/runtime `dlopen` flows) where no injectable target could be selected.  
  When the static-link intersection is empty, TrollFools now falls back to scanning eligible Mach-O files under `Frameworks/` (including top-level `.dylib`).
- Plugin management: Updated plugin removal flow to handle enabled vs disabled plugins separately:  
  enabled plugins are ejected, while disabled plugins are cleaned via desist/marker path handling.

### Added

- Advanced Settings: Added **Enable Compatibility Fallback** (default ON) to control fallback candidate behavior when no static-link match is found.
- Result-page notice: Added a subtitle under **Completed** when injection succeeds through compatibility fallback.

### Improved

- Candidate filtering: Fallback candidates now exclude `libswift*` and ignored injection-related dylib/framework names, with consistent case-insensitive handling.
- Diagnostics: Expanded Mach-O scan logs with candidate counts, file sizes, encrypted/unreadable stats, and final target selection.
- Settings clarity: Refined Advanced Settings layout and explanatory copy for better non-technical readability.
- Ads/assets: Removed built-in `Letterpress` ad entry and related localization/icon assets; refreshed marketing artwork.

### Localization

- Updated `en/zh-Hans/it/vi` strings for compatibility-fallback and settings guidance, and removed strings for deleted entries.

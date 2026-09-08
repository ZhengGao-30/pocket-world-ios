# 口袋奇遇 · Pocket World

独立原生 iPhone Demo，SwiftUI + MapKit，最低 iOS 17。围绕「地图发现 → 走近地点 → 拆开小惊喜 → 收藏 / 留下一句话」展开，同时保留明确标注的校园示范模式。暂用工作名「口袋奇遇」。

2026-09-08 原始 Demo 已完成 iPhone 17 模拟器编译、安装、实际交互和重启恢复验收；原始 7 项 XCTest 全部通过。本轮基础与 GPS 升级最终 28 项 XCTest 全部通过，详细范围见下方基础升级验收记录。原始记录见 [验收记录](Design/ACCEPTANCE-2026-09-08.md)。

## 运行

需要安装 Xcode、iOS 模拟器运行时和一个 iPhone 模拟器。当前版本已在 Xcode 26.6 / iOS 26.5 模拟器上验证。

用 Xcode 打开 `PocketWorld.xcodeproj`，选择 `PocketWorld` scheme 和 iPhone 模拟器，点击 Run 即可。模拟器运行不需要开发者账户。

也可以在仓库根目录运行（脚本使用系统 `python3` 自动选择已启动或可用的 iPhone 模拟器）：

```sh
./scripts/run-simulator.sh
```

可通过环境变量 `POCKET_WORLD_SIMULATOR_UDID` 指定模拟器，`POCKET_WORLD_DERIVED_DATA` 指定构建目录。默认构建输出在 `.build/`，不纳入 Git。

真机运行时，在 Signing & Capabilities 中选择自己的 Team，并按需要修改 bundle ID `com.pocketworld.demo`。本仓库没有附带签名证书或安装包。

## 测试

在 Xcode 中选择 iPhone 模拟器并运行 Product → Test（⌘U）。也可指定本机模拟器 UDID 执行：

```sh
xcodebuild -project PocketWorld.xcodeproj -scheme PocketWorld \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath .build CODE_SIGN_IDENTITY=- test
```

## 当前功能

- 发现：真实 Apple 地图、标题/地点搜索、类别筛选、地图中心选点；用户主动开启 iPhone 前台 GPS 漫游，位置与距离更新、精度圈、手动浏览暂停跟随；另有 UNSW 示范入口。
- 小惊喜：模拟走近、拖动或按钮打开、收藏、设备内回信。
- 口袋：收藏、自己留下的内容、打开历史及搜索；回收站可恢复自己暂时隐藏的内容，保留相关收藏和回应。
- 伙伴：原创兔子「糯糯」与水獭「栗栗」，可切换、轻点互动。
- 创建：标题、文字、物件类型、真实地图坐标与地点名称；草稿自动保存并可续写，发布后聚焦新地点。自己的内容可编辑，关闭时保护未保存的文字。
- 地图恢复：发现页与选点页可点圆形刷新按钮重新载入底图，保留当前相机；地图徽标统计当前视野内的故事。
- 原生系统状态栏、安全区、输入框与弹出页；按钮、标签与宠物反馈使用可交互动画，尊重系统减少动态效果设置。

校园种子明确标注为示范内容，并用固定起点计算示范距离。实地漫游使用手机 GPS，只显示本机内容；没有社区服务器，所以不会出现其他用户真实发布的内容。自己的内容可随时查看。用户新写的内容与回信仅存于本设备，没有向其他人发送。

数据：App 沙盒 Application Support/PocketWorld/world-state.json，原子写入。支持 v1 到 v2 数据迁移。没有账号、后台服务、跨设备同步、后台地理围栏、图片上传、推送或 App Store / TestFlight 发布。Apple 地图底图加载需要网络；本地文字与收藏不依赖社区服务器。

基础升级的检查与剩余验收见 [Design/FOUNDATION-ACCEPTANCE-2026-09-08.md](Design/FOUNDATION-ACCEPTANCE-2026-09-08.md)，地图/GPS 的状态与真机验证见 [Design/GPS-EXPLORATION.md](Design/GPS-EXPLORATION.md)。

## 原创插画

使用内置 imagegen 生成，最终提示词见 [Design/ASSET-PROMPTS.md](Design/ASSET-PROMPTS.md)。实际资源在 `PocketWorld/Assets.xcassets`：PetBunny、PetOtter、StarCapsule、AppIcon。插画为透明 PNG / 图标，宠物当前是带原生变换动画的插画，不是可自由旋转的 3D 模型。

## 技术参考

- [Apple：Map](https://developer.apple.com/documentation/mapkit/map)
- [Apple：MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition)
- [Apple：SensoryFeedback](https://developer.apple.com/documentation/swiftui/sensoryfeedback)

工程使用系统框架，无需下载第三方运行依赖。Xcode 工程已提交，可以直接使用。只有需要重新生成工程时，才需在自己的 Ruby 环境安装 `xcodeproj` gem，然后运行 `ruby scripts/generate-project.rb`。验收文档中的本机日志、测试结果包、录像和数据备份不包含在仓库中。

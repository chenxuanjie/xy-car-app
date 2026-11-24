# XY-CAR

基于 `app-foundation` 的 Flutter 地面站，支持 Android、Windows 和 Web。设置、账号和更新页使用公共 UI。地面站支持离线航点编辑。登录后可保存和读取账号下的设备配置和任务存档。

## 本地开发

将 `xy_car_app` 和 `app-foundation` 放在同一父目录。开发和构建均直接读取 `../app-foundation` 中实际用到的包，公共包的修改在那一个目录完成。确需本机使用特定版本时，可放入 `third_party/` 并通过本地覆盖文件引用。

```powershell
flutter pub get
flutter run -d chrome
flutter test
```

开发运行默认使用进程内的测试服务，账号和密码均为 `demo`。正式构建默认使用现有 `xy_car_app` 账号服务。可用 `--dart-define=XY_CAR_LIVE_ACCOUNT=true` 在开发时连接正式服务，或设为 `false` 在 Release 构建中使用测试服务。

Web 窗口宽度达到 1280 逻辑像素时，可在「系统设置 → 宽屏主题」选择 CCY。该主题沿用 CCY 原工程 `09d8f7d` 的界面与素材，游戏和监控模式使用本地演示数据。点击 CCY 底栏的「设置」可切回经典主题。

## 正式环境

- Android 沿用 `com.xycar.xy_car_app` 和原签名。签名配置及密钥放在 `android/key.properties` 和 `android/keystore/`，由本地 Git 忽略规则保护。
- Windows 可执行文件为 `xy_car_app.exe`，安装器沿用 `xy_car_app` 标识，模板位于 `packaging/windows/`。
- Web 使用同源 `/api/`，网关模板位于 `packaging/docker/`。Docker 发布入口为 `scripts/build_web_docker.ps1`，需要配套 API 工程和 Python 环境。
- 本机继续直接引用 Foundation。发布前在能访问干净依赖的副本运行 `python scripts/ci_foundation_snapshot.py snapshot`，提交 `packaging/ci` 的快照和锁定文件。GitHub Actions 按校验值恢复同级依赖，构建、验证并发布 `linux/amd64` 镜像。
- Web 镜像将 CanvasKit、字体、图片等静态资源、应用代码分成独立镜像层。NAS 首次由 GHCR 拉取完整镜像，后续按摘要复用本机已有层。
- 原生端账号服务可通过 `APP_SERVICE_ORIGIN` 或应用设置指定。发布清单沿用 `xy_car_app`，可通过 `XY_CAR_RELEASE_ORIGIN` 单独设定来源。Android 和 Windows 的正式安装包下载及安装交接仍待接入。Web 的「软件更新」页显示当前版本，检查更新不可用。

许可证为 GPL-3.0-or-later，见 [LICENSE](LICENSE)。

## Web 的 NAS 部署

在群晖现有 XY-CAR 项目中使用 [渠道 Compose](packaging/docker/docker-compose.ghcr.yml)。其镜像引用固定为 `ghcr.io/chenxuanjie/xy-car-app:nas`，每次重新应用项目会拉取该渠道并在镜像更新时重建 Web 容器。仅重启原容器会继续使用当前镜像。

常规 `v<版本>-rc.<序号>+<构建号>` 或正式版 `v<版本>+<构建号>` 标签发布版本镜像。需要更新 NAS 渠道时，推送同格式加 `web-nas-` 前缀的附注标签，或手动运行工作流并选择 `publish-nas`。渠道发布先验证 Web 镜像，再更新并核对 `:nas`。GitHub Actions 附件中的固定摘要 Compose 可用于回退到对应版。

# XY-CAR

基于 `app-foundation` 的 Flutter 地面站，支持 Android、Windows 和 Web。设置、账号和更新页使用公共 UI。地面站支持离线航点编辑和本地车辆连接记录。登录后可保存和读取账号下的任务存档。

## 本地开发

将 `xy_car_app` 和 `app-foundation` 放在同一父目录。开发和构建均直接读取 `../app-foundation` 中实际用到的包，公共包的修改在那一个目录完成。确需本机使用特定版本时，可放入 `third_party/` 并通过本地覆盖文件引用。

```powershell
flutter pub get
flutter run -d chrome
flutter test
```

开发运行默认使用进程内的测试服务，账号和密码均为 `demo`。正式构建默认使用现有 `xy_car_app` 账号服务。可用 `--dart-define=XY_CAR_LIVE_ACCOUNT=true` 在开发时连接正式服务，或设为 `false` 在 Release 构建中使用测试服务。

Web 窗口宽度达到 1280 逻辑像素时，可在「系统设置 → 宽屏主题」选择 CCY。点按顶栏 `LINK` 打开车辆连接弹窗。顶栏显示 WebSocket 往返延迟，尚未收到有效探测回包或断开时显示 `LINK —`。通过 HTTPS 托管时使用网关的 `wss://` 代理地址。

经典主题从顶栏「车辆连接」或链路状态打开同一个弹窗。点按已保存车辆即可连接。点「添加车辆」或车辆行的编辑按钮，在弹窗中填写地址后选择「保存并连接」。车辆记录保存在本机，可在弹窗中删除。两个主题共用车辆记录和实时连接。

每辆车可保存局域网和外网地址，并选择「自动」「仅局域网」或「仅外网」。自动模式在起连或断线后先试局域网，1.5 秒内没有收到首个有效 RTT 回包时再尝试外网。外网 TCP FRP 地址可填写 `ws://<域名>:10090/ws`，通过 TLS 代理时填写完整的 `wss://` 地址。状态区显示当前线路和 RTT。

可用 `flutter run -d chrome --dart-define=XY_CAR_CCY_DEMO=true` 打开原有本地驾驶舱演示。点击 CCY 底栏的「设置」可切回经典主题。

系统设置中的 Wi-Fi 页面共用当前车辆连接。在页面中可读实际 STA 和热点状态，编辑个人预设，或下发配置并在车端应用后确认。个人预设按服务地址、账号和车辆保存在本机。Windows 和 Android 可以选择在系统安全存储中记住密码。Web 配网时按次输入密码。

车端热点页面使用自带资源的 Web 构建。在本仓库执行 `flutter build web --release --no-wasm-dry-run --no-web-resources-cdn`，将 `build/web` 作为板端 Nginx 的静态根目录。手机接入车端热点后，从 `http://192.168.88.1:8888/` 进入 Wi-Fi 页面。

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

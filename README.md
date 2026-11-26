# XY-CAR

基于 `app-foundation` 的 Flutter 地面站，支持 Android、Windows 和 Web。设置、账号和更新页使用公共 UI。地面站支持车辆自动发现和离线航点编辑。登录后可保存和读取账号下的任务存档。

## 本地开发

将 `xy_car_app` 和 `app-foundation` 放在同一父目录。开发和构建均直接读取 `../app-foundation` 中实际用到的包，公共包的修改在那一个目录完成。确需本机使用特定版本时，可放入 `third_party/` 并通过本地覆盖文件引用。

```powershell
flutter pub get
flutter run -d chrome
flutter test
```

开发运行默认使用进程内的测试服务，账号和密码均为 `demo`。正式构建默认使用现有 `xy_car_app` 账号服务。可用 `--dart-define=XY_CAR_LIVE_ACCOUNT=true` 在开发时连接正式服务，或设为 `false` 在 Release 构建中使用测试服务。

Web 窗口宽度达到 1280 逻辑像素时，可在「系统设置 → 宽屏主题」选择 CCY。点按顶栏 `LINK` 打开车辆连接弹窗。顶栏显示 WebSocket 往返延迟，尚未收到有效探测回包或断开时显示 `LINK —`。

经典主题从顶栏「车辆连接」或链路状态打开同一个弹窗。打开后立即读取车辆发现列表，每 5 秒刷新。卡片显示车辆 ID、云端在线状态、网络模式、STA IP 和最后活跃时间。选择车辆会先尝试上报的局域网地址，1.5 秒内未收到同一车辆的 RTT 回包时改走云端。点击卡片的云朵按钮可直接走云端。

群晖 Web 用当前站点的同源 HTTP 和 WebSocket 地址。浏览器限制已发现车辆的私网访问时会自动切云端。Android 和 Windows 默认访问 `https://cznas.pp.ua:8090`，可用 `XY_CAR_VEHICLE_ORIGIN` 指定其他车辆服务。连接车端 Wi-Fi 后，在当前地面站点「连接车端热点」即可尝试直连 `ws://192.168.88.1:9090/ws`。Web 直连受浏览器的本地网络访问设置影响。开发时用下方 Compose 验证 Web 的同源发现和转发。

在「系统设置 → 地面站」可独立选择视频分辨率（480p、720p、1080p）和视频帧率（15、25、30 fps），默认 720p / 25 fps。经典和 CCY 界面共用这两项设置。局域网和车端热点从板端 MediaMTX 播放，外网从群晖中继播放。关闭视频或切到后台会释放公网推流。

可用 `flutter run -d chrome --dart-define=XY_CAR_CCY_DEMO=true` 打开原有本地驾驶舱演示。点击 CCY 底栏的「设置」可切回经典主题。

系统设置中的 Wi-Fi 页面共用当前车辆连接。在页面中可读实际 STA 和热点状态，编辑个人预设，或下发配置并在车端应用后确认。个人预设按服务地址、账号和车辆保存在本机。Windows 和 Android 可以选择在系统安全存储中记住密码。Web 配网时按次输入密码。

车端页面使用自带资源的 Web 构建。在本仓库执行 `flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --dart-define=XY_CAR_BOARD_WEB=true`，将 `build/web` 作为板端 Nginx 的静态根目录。从 `http://<板端局域网 IP>:8089/` 或车端热点 `http://192.168.88.1:8089/` 打开地面站，网页会自动连接板端同源 `/ws`。

## 正式环境

- Android 沿用 `com.xycar.xy_car_app` 和原签名。签名配置及密钥放在 `android/key.properties` 和 `android/keystore/`，由本地 Git 忽略规则保护。
- Windows 可执行文件为 `xy_car_app.exe`，安装器沿用 `xy_car_app` 标识，模板位于 `packaging/windows/`。
- Web 使用同源 `/api/`，网关模板位于 `packaging/docker/`。Docker 发布入口为 `scripts/build_web_docker.ps1`，需要配套 API 工程和 Python 环境。
- 本机继续直接引用 Foundation。发布前在能访问干净依赖的副本运行 `python scripts/ci_foundation_snapshot.py snapshot`，提交 `packaging/ci` 的快照和锁定文件。GitHub Actions 按校验值恢复同级依赖，构建、验证并发布 `linux/amd64` 镜像。
- Web 镜像将 CanvasKit、字体、图片等静态资源、应用代码分成独立镜像层。NAS 首次由 GHCR 拉取完整镜像，后续按摘要复用本机已有层。
- 原生端账号服务可通过 `APP_SERVICE_ORIGIN` 或应用设置指定。发布清单沿用 `xy_car_app`，可通过 `XY_CAR_RELEASE_ORIGIN` 单独设定来源。Android 和 Windows 的正式安装包下载及安装交接仍待接入。Web 的「软件更新」页显示当前版本，检查更新不可用。

许可证为 GPL-3.0-or-later，见 [LICENSE](LICENSE)。

## Web 的 NAS 部署

在群晖现有 XY-CAR 项目中使用 [渠道 Compose](packaging/docker/docker-compose.ghcr.yml)。`xy-car-web` 容器同时运行 Nginx 和单进程 FastAPI，两者通过容器内 Unix 套接字通信。每次重新应用项目会拉取渠道并在镜像更新时重建容器。仅重启原容器会继续使用当前镜像。

在 DSM 的 `https://cznas.pp.ua:8090` 到 `http://127.0.0.1:8089` 反代规则中启用 WebSocket 自定义标头。Web 容器转发同源的 `GET /api/v1/vehicles`、`/api/v1/agent/ws` 和 `/api/v1/client/ws?vehicle_id=...`。两辆车报到后，从浏览器分别连接并核对车辆 ID 和 RTT。断开网络后，从最后一次心跳起 15 秒内服务端标记离线，页面在下一次成功轮询时更新。服务重启后由车辆重新报到恢复列表。

公网视频使用同一 Compose 项目里的 `video-relay` 服务：

```sh
docker compose -f docker-compose.ghcr.yml -f docker-compose.video.yml up -d
```

在部署目录的私有 `.env` 设置 `XY_CAR_SRT_PASSPHRASE`，使用与板端相同的 10–79 位 URL 安全随机口令，板端 SRT 连接使用 `pbkeylen=16`。公网域名默认 `cznas.pp.ua`。路由器和群晖须把 `8890/UDP`（SRT 入站）及 `8189/UDP`、`8189/TCP`（WebRTC 媒体）送到群晖。Flutter 的 WHEP 信令走现有 `https://cznas.pp.ua:8090/media/`，由 Web 容器转到同网络的 `video-relay:8889`。中继一次接收一辆车的一档画质。WHEP 观看入口在推流活跃期间可公开访问，请按你的部署访问范围决定是否对外开放。

常规 `v<版本>-rc.<序号>+<构建号>` 或正式版 `v<版本>+<构建号>` 标签发布版本镜像。需要更新 NAS 渠道时，推送同格式加 `web-nas-` 前缀的附注标签，或手动运行工作流并选择 `publish-nas`。渠道发布先验证 Web 镜像，再更新并核对 `:nas`。GitHub Actions 附件中的固定摘要 Compose 可用于回退到对应版。

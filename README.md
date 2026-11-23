# XY-CAR

基于 `app-foundation` 的 Flutter 地面站，支持 Android、Windows 和 Web。设置、账号和更新页使用公共 UI。地面站支持离线航点编辑。登录后可保存和读取账号下的设备配置和任务存档。

## 本地开发

将 `app-foundation` 和本工程放在同一父目录，再运行：

```powershell
flutter pub get
flutter run -d chrome
flutter test
```

开发运行默认使用进程内的测试服务，账号和密码均为 `demo`。正式构建默认使用现有 `xy_car_app` 账号服务。可用 `--dart-define=XY_CAR_LIVE_ACCOUNT=true` 在开发时连接正式服务，或设为 `false` 在 Release 构建中使用测试服务。

## 正式环境

- Android 沿用 `com.xycar.xy_car_app` 和原签名。签名配置及密钥放在 `android/key.properties` 和 `android/keystore/`，由本地 Git 忽略规则保护。
- Windows 可执行文件为 `xy_car_app.exe`，安装器沿用 `xy_car_app` 标识，模板位于 `packaging/windows/`。
- Web 使用同源 `/api/`，网关模板位于 `packaging/docker/`。Docker 发布入口为 `scripts/build_web_docker.ps1`，需要配套 API 工程和 Python 环境。
- 原生端账号服务可通过 `APP_SERVICE_ORIGIN` 或应用设置指定。发布清单沿用 `xy_car_app`，可通过 `XY_CAR_RELEASE_ORIGIN` 单独设定来源。Android 和 Windows 的正式安装包下载及安装交接仍待接入。Web 正式版的「关于」显示版本。

许可证为 GPL-3.0-or-later，见 [LICENSE](LICENSE)。

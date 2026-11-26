# 车辆发现 Web 部署记录

日期：2026-11-26。配套候选标签：`xy-car-discovery-2026-11-26-rc.1`。

## 已部署版本

- 功能源码：`92abbc6dcac4488f257151ad1d6aecd234ab0774`，声明版本 `1.0.1+3`。
- 镜像：`ghcr.io/chenxuanjie/xy-car-app:v1.0.1-rc.13-3`，平台 `linux/amd64`。
- 摘要：`sha256:174dd66e03c1af555ba7cd6985e2f80d43afa85bea6cd6275bfc0d42a4ce77f4`。
- [GitHub Actions 构建与镜像验证](https://github.com/chenxuanjie/xy-car-app/actions/runs/45813645271)成功，NAS 渠道 `:nas` 已发布。
- 本地固定入口为 `http://localhost:8089`，已运行同一摘要镜像；群晖入口为 `https://cznas.pp.ua:8090`，宿主绑定仍为 `127.0.0.1:8089`。

本次记录提交只补充交付信息，镜像仍由上述功能提交构建，无需因文档变化重建镜像。

## 配套服务与反代

| 配套组件 | 功能源码提交 |
| --- | --- |
| xy-car-ros2 | `79f1cda07362adff0345ffadfa17589bf0e484eb` |
| app_data_service | `9ba1a0730bb9dc1381c7219ebc520a952f6c68e9` |

Web 容器只提供 Flutter 页面和 Nginx 反代。车辆注册表、心跳与 WebSocket 转发由现有独立 app_data_service 提供。群晖 Web 上游为 `http://192.168.1.55:18280`；本地容器使用同一服务的 HTTPS 入口 `https://cznas.pp.ua:18281`。

DSM 的 `8090` 与 `18281` 两条现有反代规则均已补齐 WebSocket 请求头：`Upgrade: $http_upgrade`、`Connection: $connection_upgrade`。缺少这些头时，HTTP 列表可返回 200，但 WebSocket 会以 HTTP 404 失败。

## 验证范围

- 持续搜索雷达动效、每 5 秒更新提示、查询失败和自动重试状态已纳入该镜像。
- 既有 Flutter analyze 与 20 项测试通过，2 项 Web 专用测试跳过；Actions 的 Web 构建和镜像检查通过。
- 两处 Web 的 `/api/v1/vehicles` 返回在线的 `xycar_01`；两处 WebSocket 路径均取得该车辆的 `pong`，RTT 约 45–47 ms。
- 群晖视频日志确认 WebRTC 连接建立并读取 H.264；公网中继回读成功解码 25 帧。板端 SRT 配置错误已在设备上修正为 `pbkeylen=16`，本修复不涉及 Web 源码。

浏览器视觉检查曾被用户按 Escape 中止；未据此宣称完成页面视觉验收。独立蜂窝网络浏览器播放和两台实车切换尚未实测。

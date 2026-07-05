<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.9+-00E5FF?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.9+-7C4DFF?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/License-MIT-00E676?logo=opensourceinitiative&logoColor=white" alt="License">
</p>

# Kopy
pc复制内容自动同步到手机端

> PC ↔ 手机 剪贴板实时同步 · 文件互传 · 屏幕投屏

Kopy 是一个**跨平台设备协作工具**，基于 Flutter 构建，支持 Android、iOS、macOS、Windows 和 Linux。在局域网内实现剪贴板双向实时同步、文件安全互传，以及手机摄像头画面实时投屏到电脑浏览器。

---

## ✨ 功能

| 功能 | 描述 |
|------|------|
| 🔄 **剪贴板同步** | PC ↔ 手机剪贴板双向实时同步，支持二维码扫码连接 |
| 📁 **文件互传** | 局域网内图片、文档、视频等文件的安全双向传输 |
| 📡 **屏幕投屏** | 手机摄像头画面实时推流到电脑浏览器查看 |

## 🎨 设计

深空霓虹仪表盘风格，毛玻璃卡片 + 动态光晕粒子 + 霓虹点缀。所有界面均为深色主题，流畅动画交互。

## 🚀 快速开始

### 环境要求

- Flutter SDK ≥ 3.9
- Dart SDK ≥ 3.9
- Android Studio / Xcode（对应平台构建）

### 安装依赖

```bash
cd Kopy
flutter pub get
```

### 运行

```bash
# 手机端
flutter run

# 桌面端（macOS / Windows / Linux）
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

### 构建发布

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# macOS
flutter build macos --release
```

---

## 🏗 架构

```
┌─────────────────────────────────────┐
│            桌面端 (Server)            │
│  ┌─────────────────────────────────┐ │
│  │  HTTP Server (port 9876)        │ │
│  │  ├ GET  /clipboard              │ │
│  │  ├ GET  /ws          (实时推送)  │ │
│  │  ├ POST /upload                 │ │
│  │  ├ GET  /files                  │ │
│  │  ├ GET  /files/{name}           │ │
│  │  └ DELETE /files/{name}         │ │
│  └─────────────────────────────────┘ │
│              ↕ WebSocket              │
│  ┌─────────────────────────────────┐ │
│  │  手机端 (Client)                 │ │
│  │  ├ 接收实时剪贴板推送              │ │
│  │  ├ 上传/下载文件 (HTTP)           │ │
│  │  └ 扫描二维码自动连接             │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 桌面端
- 启动 HTTP + WebSocket 服务（端口 9876）
- 实时监控本机剪贴板变化，通过 WebSocket 广播
- 接收手机端粘贴内容并写入系统剪贴板
- 提供文件上传/下载/列表/删除接口

### 移动端
- WebSocket 长连接接收 PC 剪贴板实时推送
- 自动写入系统剪贴板
- 每 2 秒检测本机剪贴板变化并推送到 PC
- Android 前台服务保持后台连接不中断

### 文件传输
- 桌面端：文件直接存储到本地 `clipboard_files` 目录
- 移动端：通过 HTTP multipart 上传 / 流式下载
- 支持重名自动重命名（时间戳后缀）

---

## 📂 项目结构

```
lib/
├── main.dart                          # 应用入口 & 主题配置
├── home_page.dart                     # 首页 — 深空霓虹仪表盘
├── clipboard_sync/
│   ├── clipboard_sync_service.dart    # HTTP/WebSocket 服务核心
│   ├── clipboard_sync_provider.dart   # Riverpod 状态管理
│   ├── clipboard_sync_page.dart       # 剪贴板同步 UI（霓虹玻璃）
│   ├── background_service.dart        # 后台服务初始化
│   ├── foreground_service_bridge.dart # Android 前台服务桥接
│   └── qr_scanner_page.dart           # 二维码扫描页
└── screen_mirror/
    ├── mirror_service.dart            # 投屏 WebSocket 服务
    └── screen_mirror_page.dart        # 投屏控制 UI（宇宙广播）
```

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源。

### 依赖库及其协议

| 包名 | 协议 |
|------|------|
| flutter_riverpod | MIT |
| file_picker | MIT |
| open_filex | MIT |
| path_provider | BSD-3-Clause |
| qr_flutter | BSD-3-Clause |
| mobile_scanner | MIT |
| camera | BSD-3-Clause |

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request。

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/amazing`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing`)
5. 创建 Pull Request

---

<p align="center">Made with ❤️ using Flutter</p>

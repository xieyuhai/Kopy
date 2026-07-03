# 贡献指南

感谢你对 Kopy 的关注！

## 开发环境

- Flutter SDK ≥ 3.9
- Dart SDK ≥ 3.9
- Android Studio 或 VS Code

## 本地开发

```bash
# 克隆项目
git clone https://github.com/xieyuhai/Kopy.git
cd Kopy

# 安装依赖
flutter pub get

# 运行代码生成（Riverpod）
dart run build_runner build

# 启动开发
flutter run
```

## 代码风格

项目使用 `flutter_lints` 进行代码检查：

```bash
flutter analyze
```

## 提交流程

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -m 'feat: xxx'`)
4. 推送到分支 (`git push origin feature/xxx`)
5. 创建 Pull Request

## Commit 规范

- `feat:` 新功能
- `fix:` 修复
- `refactor:` 重构
- `docs:` 文档
- `style:` 格式

## 项目结构

```
lib/
├── main.dart                          # 应用入口
├── home_page.dart                     # 首页
├── clipboard_sync/                    # 剪贴板同步模块
│   ├── clipboard_sync_service.dart    # 核心服务
│   ├── clipboard_sync_provider.dart   # 状态管理
│   ├── clipboard_sync_page.dart       # UI 页面
│   ├── background_service.dart        # 后台服务
│   ├── foreground_service_bridge.dart # 前台服务桥接
│   └── qr_scanner_page.dart           # 二维码扫描
└── screen_mirror/                     # 屏幕投屏模块
    ├── mirror_service.dart            # 投屏服务
    └── screen_mirror_page.dart        # 投屏 UI
```

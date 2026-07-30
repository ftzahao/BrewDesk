# BrewDesk

一款原生 macOS Homebrew 图形化管理客户端，基于 SwiftUI 构建。

## 功能

- **已安装** — 浏览所有通过 Homebrew 安装的 Formula 和 Cask，查看依赖关系并一键卸载
- **可更新** — 检测过时的包，支持单个或全部升级
- **搜索** — 从 Homebrew 核心仓库及已添加的 Tap 中搜索包
- **Taps** — 管理 Homebrew Tap，添加 / 移除第三方仓库
- **服务** — 启动、停止、重启 Homebrew 管理的后台服务（如数据库、消息队列等）
- **维护** — 运行 `brew doctor`，清理缓存，释放磁盘空间
- **设置** — 自定义 Homebrew 路径、镜像源等配置

## 系统要求

- macOS 14.0+
- Xcode 15.0+
- 已安装 Homebrew（[brew.sh](https://brew.sh)）

## 快速开始

```bash
git clone https://github.com/ftzahao/BrewDesk.git
cd BrewDesk
open BrewDesk.xcodeproj
```

在 Xcode 中选择目标设备为 **My Mac**，点击 Run 即可。

## 项目结构

```
BrewDesk/
├── Core/               # 核心业务逻辑
│   ├── AppState.swift      # 全局状态管理
│   ├── Brew/               # Homebrew CLI 交互层
│   │   ├── BrewClient.swift    # 命令行调用封装
│   │   ├── BrewJSON.swift      # JSON 输出解析
│   │   ├── BrewLocator.swift   # brew 可执行文件定位
│   │   └── DoctorParser.swift  # brew doctor 输出解析
│   └── Models/             # 数据模型
├── Features/           # 各功能页面视图
│   ├── Installed/
│   ├── Outdated/
│   ├── Search/
│   ├── Taps/
│   ├── Services/
│   ├── Maintenance/
│   ├── Settings/
│   └── Setup/              # 首次启动引导
└── UI/                 # 可复用 UI 组件
    ├── Components/
    └── MenuBar/            # 菜单栏快捷入口
```

## 构建脚本

项目提供 `build.sh` 脚本，支持命令行构建与打包：

```bash
./build.sh build      # 构建 Release 版本（默认）
./build.sh debug      # 构建 Debug 版本
./build.sh clean      # 清理构建产物
./build.sh archive    # 归档为 .xcarchive
./build.sh export     # 从归档导出 .app
./build.sh dmg        # 构建并打包为 .dmg 安装镜像
```

## 许可证

MIT License

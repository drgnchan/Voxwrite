# Linux / Flutter 桌面开发避坑指南

本指南整理自实际开发与验收中踩过的坑，适用于 **Flutter Linux 桌面应用 + KDE Plasma (Wayland)** 场景。
大部分条目是通用经验（任何 Flutter Linux / KDE 项目都适用），VoxWrite 相关内容作为示例标注。

---

## 1. 窗口关闭与后台驻留（Flutter Linux）

### 1.1 在 C++ 里拦 `delete-event` 是无效的 ⚠️
Flutter Linux 引擎（`fl_view.cc`）**自己接管了 `delete-event`**，返回 `TRUE` 并调用
`fl_engine_request_app_exit()`，然后通过 `System.requestAppExit`（可取消）通知 Dart 侧。
- 你在 `my_application.cc` 里再连一个 `delete-event` handler **永远不会触发**（引擎的先执行并吃掉事件）。
- 结论：**在 C++ 拦关窗是死路**，必须走 Dart。

### 1.2 正确做法：Dart 侧取消退出 + 平台通道隐藏窗口
```dart
import 'dart:ui' show AppExitResponse;  // AppExitResponse 在 dart:ui，必须显式 import

AppLifecycleListener(
  onExitRequested: () async {
    await lifecycleChannel.invokeMethod('hideWindow'); // C++ 里 gtk_widget_hide
    return AppExitResponse.cancel;                     // 阻止退出
  },
);
```
- `AppLifecycleListener` 构造时把自己注册进 `WidgetsBinding` 的观察者列表（**强引用**），
  不需要自己持有全局引用，否则 `flutter analyze` 会报 `unused_element`。
- `onExitRequested` 在本版本签名是 `Future<AppExitResponse> Function()`（无参数）。
- 关窗后窗口对象仍在（GTK 没销毁它），托盘“打开”时 `gtk_widget_show` + `gtk_window_present` 即可恢复。

### 1.3 判断产物新旧要看对地方
- **Dart 改动**编译进 `bundle/lib/libapp.so`（release AOT），**不是可执行文件**。
  看可执行文件 mtime 判断“是否包含最新 Dart 代码”是错的，要比较 `libapp.so` 的时间戳。
- C++ 改动才体现在 `bundle/voxwrite` 可执行文件上。

---

## 2. KDE 系统托盘（ayatana-appindicator / StatusNotifierItem）

### 2.1 依赖
- 构建：`libayatana-appindicator-gtk3-devel`（提供头文件 + pkg-config `ayatana-appindicator3-0.1`）
- 运行：`libayatana-appindicator-gtk3`
- CMake：`pkg_check_modules(APPINDICATOR REQUIRED IMPORTED_TARGET ayatana-appindicator3-0.1)`

### 2.2 构造器被标记 deprecated 导致 `-Werror` 编译失败
`app_indicator_new` / `app_indicator_new_with_path` 都带 `G_GNUC_DEPRECATED`，
Flutter 模板默认 `-Wall -Werror` 会直接编不过。它们仍是官方推荐 API，用 pragma 压掉警告：
```c
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
self->indicator = app_indicator_new("...", "...", APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
#pragma GCC diagnostic pop
```

### 2.3 自定义图标：路径必须以 `icons` 结尾 + 完整 hicolor 主题 ⚠️
KDE 的 StatusNotifierItem host（`plasma-workspace/applets/systemtray/statusnotifieritemsource.cpp`）
源码里有一句 FIXME：**“If last part of path is not 'icons', this won't work!”**
- `app_indicator_set_icon_theme_path()` 的路径**必须以 `icons` 结尾**，否则 KDE 不会建立自定义图标加载器。
- 目录里必须放**完整 hicolor 主题**（`index.theme` + `<size>/apps/*.png`），只放一个平铺 PNG 无法解析。
- 结构示例（bundle 内）：
  ```
  bundle/data/icons/hicolor/index.theme
  bundle/data/icons/hicolor/<size>x<size>/apps/<icon-name>.png   # 如 128x128/apps/voxwrite-tray.png
  ```
- 不要用 `g_object_new(APP_INDICATOR_TYPE, "category", <int>, ...)` 传枚举：GLib 的
  `g_object_new` varargs 里**枚举属性按字符串 nick 传**（如 `"ApplicationStatus"`），
  传 int 0 会触发 `g_enum_get_value_by_nick(NULL)` 断言 + 段错误。
- 图标解析失败时（无 watcher / 路径不对）appindicator 不会导出 IconPixmap，托盘显示空白/系统图标。

### 2.4 托盘诊断命令（KDE）
```bash
# 查看已注册的 SNI 项（我们的在 /org/ayatana/NotificationItem/<id>）
gdbus call --session --dest org.kde.StatusNotifierWatcher --object-path /StatusNotifierWatcher \
  --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
# 查看托盘项的图标属性
gdbus call --session --dest <bus名> --object-path /org/ayatana/NotificationItem/dev.raymond.voxwrite \
  --method org.freedesktop.DBus.Properties.GetAll org.kde.StatusNotifierItem
# 触发托盘菜单项（dbusmenu）：id 从 GetLayout 拿
gdbus call --session --dest <bus> --object-path .../Menu --method com.canonical.dbusmenu.GetLayout 0 -1 '[]'
```

---

## 3. KDE Wayland 自动化测试技巧

### 3.1 截图
- **`spectacle -b -n -o 文件.png`** 在 KDE Wayland 上可用（后台无交互截图）。
- `grim` 需要 compositor 开放 screen-capture 协议，默认会报 “compositor doesn't support...”。
- `import`（ImageMagick）走 XWayland，对本机 Wayland 窗口不可靠。
- 分析截图用像素扫描（PIL）比靠“肉眼 + vision”更确定，但要小心阈值（小尺寸的深色图标
  可能扫不出来，例如 22px 的紫色渐变在暗面板上饱和度偏低）。

### 3.2 窗口控制：kdotool
- `kdotool search --class voxwrite` / `windowclose` / `windowactivate` / `getwindowgeometry`
- 注意：`kdotool search` 无结果时**退出码仍是 0**，别用 `&&/||` 判断“窗口在不在”，要判断输出是否为空。
- 坐标是逻辑坐标（含缩放），物理像素 = 逻辑 × 缩放系数；屏幕截图坐标才是物理像素。

### 3.3 全局快捷键（xdg-desktop-portal GlobalShortcuts）
- 注册后在 KDE 里能看到组件：`gdbus introspect --dest org.kde.kglobalaccel --object-path /component/<app-id>`
- `allShortcutInfos` 可看到绑定的键；**`invokeShortcut <name>` 可直接触发**，是测试捷径
  （等价于模拟按下，比注入物理键可靠）。
- 绑定保存在 `~/.config/kglobalshortcutsrc`。
- 关窗后进程存活 → portal 会话与快捷键绑定**自动保持**，无需重绑。

### 3.4 验证录音/音频
- `pactl list source-outputs` 看是否有活跃录音流（VoxWrite 是 16kHz mono）。
- **注意 locale**：中文环境表头是 `信源输出`，`grep "Source Output"` 会得到 0 条，误以为没在录音。

### 3.5 进程判断
- **用 `pgrep -x <进程名>`，不要用 `pgrep -f <路径>`**：`-f` 会把 `bash -c "…/voxwrite"` 这种
  包装进程也匹配上，取到错误的 PID，造成“进程死了”的误判。

---

## 4. ydotool（uinput 键鼠注入）

- **keycode 是 Linux input event code，不是 X keycode**：
  F7=65、F8=66、F9=67、LeftMeta=125。用错一个数字会排查半天。
- 鼠标 `--absolute` 坐标是 **0-65535 空间**，不是屏幕像素：
  `ydotool 坐标 = 物理像素 / 屏幕宽高 × 65535`。
- 注入全局快捷键时，按下与松开最好分开调用并加延时（`key 66:1` → sleep → `key 66:0`），
  瞬时按下可能被 compositor 漏掉。
- 验证注入是否生效：在可输入窗口里 `ydotool type` 或按 Super 看是否弹出 KRunner。

---

## 5. 部署 / 打包（RPM）

### 5.1 用户点的是哪个版本？先查启动链路 ⚠️
KDE 常用程序 → `.desktop` 的 `Exec` → `/usr/bin/<name>`（软链）→ 实际安装位置。
**开发 bundle 和系统安装是两套东西**：改动只在 `build/.../bundle` 里，用户从启动器点开仍是旧版。
排查顺序：
```bash
command -v voxwrite          # /usr/bin/voxwrite
readlink -f /usr/bin/voxwrite  # /opt/voxwrite/voxwrite
rpm -q voxwrite              # 版本
```

### 5.2 打包要点
- Flutter release bundle 直接打成 source tar（顶层目录 `voxwrite-<ver>/`），spec 的 `%install`
  整体 `cp -a` 到 `/opt/<name>`。
- **新增动态库依赖要写进 spec 的 `Requires`**（例如托盘加的 `libayatana-appindicator-gtk3`），
  否则在干净机器上安装/运行会失败。
- `rpmbuild` 默认 topdir 可能是 `~/rpmbuild` 而不是你的 `~/build/rpmbuild`：
  用 `rpmbuild -ba --define "_topdir /path/to/rpmbuild" SPECS/xxx.spec`。
- 每个功能版本号 + changelog 一起 bump，方便用户确认“启动器里是新版”。

### 5.3 调查命令别执行 GUI 二进制
Flutter Linux 二进制**不认 `--version`**，执行它会直接启动 GUI 并把命令挂死。
调查时用 `strings` / `ldd` / `rpm -q`，不要运行它；如果误跑，先 `pkill -x voxwrite`。

---

## 6. 会话效率小贴士（来自本次踩坑）

- **后台启动 + 校验不要写在同一条命令里**：`nohup … & disown` 之后的 `sleep` 和检查会与
  后台任务竞争导致输出丢失/时序错乱。先单独启动，再单独验证。
- **不要用 `g_object_new` 猜 GObject 属性名**：先查头文件确认构造器/属性，必要时用
  `#pragma` 压掉 deprecated 警告，比在 varargs 上反复试错快。
- 遇到“行为不确定（有时活有时死）”先怀疑**检查对象错了**（如 pgrep 匹配到包装进程），
  而不是代码本身。
- 依赖图标文件路径时，从 `/proc/self/exe` 解析 bundle 目录（`g_file_read_link` +
  `g_path_get_dirname`），并让代码在文件缺失时优雅回退（如回退到系统主题图标名）。

# KeyboardLocker

清洁键盘时点一下菜单栏图标，所有按键立刻失去响应；再点一下恢复。
只有一个菜单栏图标，没有窗口、没有 Dock 图标、不会弹任何提示。

[English](README.md)

![未锁定与锁定状态的菜单栏图标](docs/menubar.png)

## 为什么需要它

擦键盘时总会压到按键——打开一堆窗口、触发快捷键、把半句话打进编辑器。
把键盘整体锁住比小心擦拭省事得多。

## 功能

- **点一下就锁**：点击菜单栏图标在锁定 / 解锁之间切换
- **拦下全部按键**：字母数字、修饰键、功能键、音量 / 亮度等媒体键
- **一眼看出状态**：平时是线框白色键盘，锁定时变成实心红色键盘

右键图标只有两项：锁定 / 解锁、退出。

## 环境要求

- macOS 13 或更高版本
- Xcode 命令行工具

## 构建

```bash
./build.sh              # 构建到 build/KeyboardLocker.app
./build.sh --run        # 构建后直接启动
./build.sh --install    # 构建后安装到 /Applications 并启动
```

## 权限

拦截键盘事件需要系统授权，首次启动会弹出引导窗口：

1. 在「系统设置 › 隐私与安全性 › 辅助功能」中打开 KeyboardLocker
2. 若列表中没有它，到「输入监控」里同样打开
3. 回到应用点击「重新检测」

> 构建脚本默认使用 ad-hoc 签名。**每次重新编译后系统会把应用视为新程序，需要重新勾选权限。**
>
> 如果频繁改代码，可以先在「钥匙串访问」里创建一个代码签名证书（名称随意，
> 例如 `KeyboardLocker Dev`），构建脚本会自动检测并使用它——
> 这样权限在重新编译后依然有效。

## 使用

| 操作 | 结果 |
| --- | --- |
| 左键点击图标 | 锁定 / 解锁 |
| 右键点击图标 | 打开菜单（锁定、退出） |
| 鼠标悬停 | 显示当前状态 |

锁定状态下鼠标、触控板仍然可用，菜单栏图标依然可以点击，解锁不受影响。

## 安全设计

键盘被锁住却解不开是这类工具最糟糕的故障，所以留了几层兜底：

- **进程结束即恢复**：event tap 跟随进程生命周期，应用退出或崩溃后键盘立刻恢复正常
- **锁屏 / 睡眠自动解锁**：屏幕锁定、显示器睡眠、系统休眠时立即解锁，保证回来能输入登录密码
- **锁屏检测双保险**：除了系统锁屏通知，锁定期间每秒还会查一次会话状态做兜底，最坏 1 秒内一定解锁
- **屏幕已锁时拒绝上锁**：此时用户唯一需要的就是键盘能打密码
- **退出菜单始终可达**：右键菜单里的「退出」不受键盘锁定影响

## 已知限制

- **电源键、Touch ID、触控板**不在拦截范围内，这是系统层面的设计
- 密码框处于活跃状态时，macOS 的「安全输入」会切断 event tap，这期间按键会漏过去
- 少数第三方键盘的厂商自定义键走私有通道，可能绕过事件层

## 自检

想确认拦截是否真的生效：

```bash
./build/KeyboardLocker.app/Contents/MacOS/KeyboardLocker --selftest
```

它会创建拦截器、注入 20 个模拟按键事件并统计拦截数量，
输出 `PASS` 表示全部拦下（退出码 0）。

## 发布新版本

前置条件：工作区干净、位于 `main` 且与远程同步、已执行 `gh auth login`。

建议先在 `CHANGELOG.md` 里写好对应版本的段落（不写的话脚本会用 `git log` 自动生成条目）：

```markdown
## 1.0.1 — 2026-11-04

- 这次改了什么
```

然后预览、发布：

```bash
./release.sh 1.0.1 --dry-run   # 只预览说明和动作，不改文件、不推送
./release.sh 1.0.1             # 改版本号 → 构建 → 打 tag → 推送 → 创建 Release
./release.sh patch             # 也可以写 minor / major，基于最新 tag 自动递增
```

脚本会依次：把 `CFBundleShortVersionString` / `CFBundleVersion` 写进 `Info.plist` 并提交、以 ad-hoc 签名重新构建、
打包 `KeyboardLocker.zip` 和 `.sha256`、创建附注 tag、推送分支与 tag、
最后用 CHANGELOG 对应段落（附加固定的安装说明）创建 GitHub Release。

| 参数 | 作用 |
| --- | --- |
| `--dry-run` | 只构建并预览，不提交、不打 tag、不推送 |
| `--notes-file FILE` | 用自己写好的完整 Release 说明 |
| `--draft` | 创建为草稿，不对外发布 |
| `-y` | 跳过确认提示 |

## 实现要点

- `KeyboardLockEngine` — 用 `CGEvent.tapCreate` 在 `.cghidEventTap` 层建立常驻事件拦截，
  位于系统快捷键处理之前，因此 ⌘Tab、⌘Q 之类同样会被吞掉。
  tap 挂在独立线程的 runloop 上，主线程卡顿不影响拦截。
- 锁定 / 解锁只翻转一个带锁的标志位，不创建、不销毁 tap，切换没有延迟也不会失败。
- 系统在回调超时时会临时禁用 tap，回调里会立即重新启用，避免键盘「悄悄解锁」。
- 菜单栏图标用 template 蒙版 + CoreGraphics 染色，锁定时把键盘符号烧成红色位图再交给按钮
  （直接给带 palette 的 SF Symbol，菜单栏会按 template 规则重渲染，红色会退回白色）。
  两种状态共用同一画布尺寸，否则 `NSStatusItem` 在二次切换时会把按钮宽度算错、图标消失。
- **解锁时补发修饰键松开**：锁定那一刻按住的 ⌘ / ⇧ / ⌥ / ⌃，其 keyUp 会被吞掉，
  系统会一直以为它被按住。解锁后主动广播一次空 flags 并逐个补 keyUp，让状态归位。
  Caps Lock 是开关而非按住，不参与归零。

## 项目结构

```
Sources/
  main.swift                     入口
  AppDelegate.swift              菜单栏、菜单、系统事件
  KeyboardLockEngine.swift       CGEventTap 拦截引擎
  StatusIcon.swift               菜单栏图标的状态与绘制
  PermissionWindow.swift         权限引导窗口
  SelfTest.swift                 命令行自检
Resources/Info.plist             应用元信息
Tools/make-icon.swift            应用图标生成
Tools/make-readme-figure.swift   README 状态图生成
build.sh                         构建脚本
release.sh                       版本号更新、打包与 GitHub 发布
```

## 许可证

[MIT](LICENSE)

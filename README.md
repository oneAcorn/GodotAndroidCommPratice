# Godot 嵌入 Android + 双向通信示例

Android 为宿主 App,Godot 4.7 引擎作为库嵌入(官方 godot-lib 路线),
Godot 场景展示 3 个模型,Android 侧用 Toast 演示业务代码,两边互相调用。

## 目录结构

```
android-communication/   Godot 4.7 工程(Mobile 渲染器)
├── scenes/main.tscn             主场景(全部内容在 scripts/main.gd 里用代码搭建)
├── scripts/main.gd              场景搭建 + 输入 + 模型拾取 + UI
├── scripts/android_bridge.gd    自动加载单例:通信桥(桌面运行时是模拟模式)
├── assets/model/                3 个 glb 模型
└── export_presets.cfg           "Android" 导出预设(只用来导 PCK)

android_project/          Android 宿主(Kotlin + Gradle KTS,AGP 9)
├── app/src/main/java/.../MainActivity.kt          继承 GodotActivity 的宿主 Activity
├── app/src/main/java/.../AndroidBridgePlugin.kt   GodotPlugin 插件(通信核心)
├── app/src/main/res/layout/activity_main.xml       godot_fragment_container + 业务按钮
└── app/src/main/assets/main.pck                    Godot 导出的工程包(构建产物)
```

## 双向通信原理

插件 `AndroidBridgePlugin` 注册后成为 Godot 引擎单例,名字为 `AndroidBridge`:

| 方向 | 机制 | 代码位置 |
|---|---|---|
| Godot → Android | GDScript 调用插件的 `@UsedByGodot` 方法,支持返回值 | `android_bridge.gd` → `AndroidBridgePlugin.kt` |
| Android → Godot | 插件 `emitSignal(声明过的 SignalInfo)`,GDScript `connect` | `pushMessageToGodot()` → `main.gd` |

GDScript 侧获取插件:`Engine.get_singleton("AndroidBridge")`(见 `android_bridge.gd`)。
插件由宿主 Activity 通过 `GodotHost#getHostPlugins()` 交给引擎注册,无需 Manifest meta-data。
注意引擎初始化早于 Godot 场景就绪,所以 Android 早期发往 Godot 的消息会先进
`pendingMessages` 缓冲,`onGodotMainLoopStarted()` 后统一发出。

## 构建与运行

```bash
# 1. Godot 工程 → PCK(改动 Godot 侧代码后执行)
"E:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" ^
  --headless --path android-communication ^
  --export-pack "Android" "android_project\app\src\main\assets\main.pck"

# 2. Android 构建安装
cd android_project
gradlew.bat assembleDebug
adb install -r app\build\outputs\apk\debug\app-debug.apk

# 3. 可选:用 Intent 触发一次 Android → Godot 业务推送
adb shell am start -n com.acorn.godot.communication/.MainActivity --es push_message hello
```

## 踩过的坑(重要)

1. **`--main-pack` 必须写 `res://main.pck`**,不能写裸相对路径 `main.pck`:
   引擎在原生层初始化**之前**会用 `StorageScope` 判断 pack 路径,相对路径会走到
   `GodotLib.getProjectResourceDir()` 的原生调用,此时 `OS` 单例还没创建,
   直接 SIGSEGV(空指针)闪退。`res://` 前缀在模板构建下被识别为 ASSETS 域,
   提前返回,绕过该调用。
2. godot-lib 从 Godot 4.x 起发布在 **MavenCentral**:`org.godotengine:godot:4.7.2.stable`,
   文件名带 `template_release` 的 AAR 就是它(网上老教程的 `godot-lib.xxx.release.aar`
   直链已 404)。
3. `getCommandLine()` 的 Kotlin 签名返回 `MutableList<String>`(不是 `List`)。
4. Godot 工程默认手持方向是横屏;本项目在 project.godot 里改成
   `window/handheld/orientation=1`(竖屏),与宿主 Manifest 的 `fullUser` 配合。
5. PCK 导出前记得开启 `textures/vram_compression/import_etc2_astc`,否则手机上
   纹理可能无法压缩采样(本项目已开启)。
6. MIUI 真机用 `adb shell input tap` 注入触摸需在手机上额外开启
   "USB 调试(安全设置)",否则报 SecurityException。

extends Node
## Godot ⇄ Android 双向通信桥(自动加载单例,见 project.godot [autoload])。
##
## Android 侧有一个名为 "AndroidBridge" 的 GodotPlugin
## (android_project/app/src/main/java/.../AndroidBridgePlugin.kt)。
## 插件由宿主 Activity 通过 GodotHost#getHostPlugins() 注册,注册后成为
## 引擎单例,用 Engine.get_singleton("AndroidBridge") 获取:
##   - GDScript 调用插件的 @UsedByGodot 方法          → Godot 发往 Android
##   - 插件 emitSignal(...) 声明过的 SignalInfo 信号  → Android 发往 Godot
##
## 编辑器/桌面运行(F5)时插件不存在,这里提供"模拟模式":调用落到 print,
## 信号照常发出,方便在电脑上预览完整流程。

## Android 主动推送的消息(来源:AndroidBridgePlugin.pushMessageToGodot)
signal message_from_android(text: String)
## Android 弹出 Toast 后的回执(Godot → Android → Godot 完整往返)
signal toast_shown(text: String)

var _plugin: Object = null


func _ready() -> void:
	if Engine.has_singleton("AndroidBridge"):
		_plugin = Engine.get_singleton("AndroidBridge")
		_plugin.message_from_android.connect(_forward_message)
		_plugin.toast_shown.connect(_forward_toast)
		print("[AndroidBridge] 已连接 Android 插件")
	else:
		print("[AndroidBridge] 未检测到 Android 插件,进入桌面模拟模式")


func is_android_available() -> bool:
	return _plugin != null


## Godot → Android:让 Android 弹一个 Toast(业务层可换成任意逻辑)
func show_toast(text: String) -> void:
	if _plugin:
		_plugin.show_toast(text)
	else:
		print("[AndroidBridge][模拟] show_toast: %s" % text)
		toast_shown.emit(text)


## Godot → Android:把"用户点击了某模型"交给 Android 业务层处理
func notify_model_clicked(model_name: String) -> void:
	if _plugin:
		_plugin.notify_model_clicked(model_name)
	else:
		print("[AndroidBridge][模拟] notify_model_clicked: %s" % model_name)
		message_from_android.emit("[业务回执] 已处理对模型 %s 的点击(模拟)" % model_name)


## Godot → Android:调用 Android 方法并同步取返回值
func get_device_info() -> String:
	if _plugin:
		return _plugin.get_device_info()
	return "桌面环境(非 Android 设备)"


func _forward_message(text: String) -> void:
	message_from_android.emit(text)


func _forward_toast(text: String) -> void:
	toast_shown.emit(text)

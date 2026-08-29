package com.acorn.godot.communication

import android.os.Build
import android.util.Log
import android.widget.Toast
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot ⇄ Android 双向通信插件。
 *
 * 注册方式:宿主 Activity 通过 [GodotHost#getHostPlugins] 把实例交给引擎
 * (见 MainActivity#getHostPlugins)。注册成功后:
 *  - GDScript 侧用 Engine.get_singleton("AndroidBridge") 拿到本插件;
 *  - 带 @UsedByGodot 的 public 方法可被 GDScript 直接调用(Godot → Android);
 *  - getPluginSignals() 声明的信号用 emitSignal 发出,GDScript 可 connect
 *    (Android → Godot)。
 */
class AndroidBridgePlugin private constructor(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "AndroidBridge"

        @Volatile
        private var instance: AndroidBridgePlugin? = null

        fun ensureRegistered(godot: Godot) {
            if (instance == null) {
                instance = AndroidBridgePlugin(godot)
            }
        }

        fun getInstance(): AndroidBridgePlugin? = instance
    }

    override fun getPluginName(): String = "AndroidBridge"

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(
        SignalInfo("toast_shown", String::class.java),
        SignalInfo("message_from_android", String::class.java),
    )

    /**
     * Godot 场景就绪比引擎初始化晚几秒。在此之前收到的业务消息先进入缓冲,
     * 等 onGodotMainLoopStarted(Godot 主循环已跑起来、GDScript 已能连信号)
     * 再统一发出,避免消息在无人监听时丢失。
     */
    private val pendingMessages = mutableListOf<String>()
    private var mainLoopStarted = false

    override fun onGodotMainLoopStarted() {
        super.onGodotMainLoopStarted()
        synchronized(pendingMessages) {
            mainLoopStarted = true
            for (message in pendingMessages) {
                emitSignal("message_from_android", message)
            }
            pendingMessages.clear()
        }
    }

    // ============ Godot → Android(被 GDScript 调用的方法)============

    @UsedByGodot
    fun show_toast(message: String) {
        Log.d(TAG, "show_toast: $message")
        runOnUiThread {
            Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
            // 回执:Godot → Android → Godot 完整往返
            emitSignal("toast_shown", message)
        }
    }

    @UsedByGodot
    fun notify_model_clicked(model_name: String) {
        // 业务代码占位:真实项目里,这里替换成你自己的 Android 业务逻辑
        Log.d(TAG, "业务处理: Godot 点击了模型 $model_name")
        runOnUiThread {
            Toast.makeText(activity, "[业务] 收到模型点击: $model_name", Toast.LENGTH_SHORT).show()
            emitSignal("message_from_android", "[业务回执] 已处理对模型 $model_name 的点击")
        }
    }

    @UsedByGodot
    fun get_device_info(): String =
        "${Build.MANUFACTURER} ${Build.MODEL} / Android ${Build.VERSION.RELEASE}"

    // ============ Android → Godot(由 Android 侧 UI/业务触发)============

    fun pushMessageToGodot(message: String) {
        Log.d(TAG, "pushMessageToGodot: $message")
        synchronized(pendingMessages) {
            if (mainLoopStarted) {
                emitSignal("message_from_android", message)
            } else {
                pendingMessages.add(message)
            }
        }
    }
}

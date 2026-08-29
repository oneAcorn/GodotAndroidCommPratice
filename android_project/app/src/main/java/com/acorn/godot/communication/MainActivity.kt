package com.acorn.godot.communication

import android.os.Bundle
import android.widget.Button
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 宿主 Activity:继承 GodotActivity,把 Godot 引擎嵌入自己的应用。
 *
 * - [getCommandLine]:告诉引擎去 assets 里加载哪份 Godot 工程(main.pck);
 * - [getGodotAppLayout]:自定义布局,必须包含 id 为 godot_fragment_container
 *   的容器(GodotFragment 的挂载点),其余部分就是普通 Android UI;
 * - [getHostPlugins]:把 AndroidBridgePlugin 交给引擎注册;
 * - [onGodotSetupCompleted]:引擎就绪后,写普通的 Android 业务代码。
 */
class MainActivity : GodotActivity() {

    override fun getCommandLine(): MutableList<String> {
        val commandLine = super.getCommandLine()
        // main.pck 位于 app/src/main/assets/,由 Godot 的
        // `--export-pack "Android"` 导出(见 android-communication/export_presets.cfg)。
        // 注意必须用 res:// 前缀:引擎在原生层初始化前会用 StorageScope 判断
        // pack 路径,裸相对路径会触发未初始化的原生调用导致 SIGSEGV,
        // res:// 在模板构建下会被识别为 ASSETS 域直接返回。
        commandLine.add("--main-pack")
        commandLine.add("res://main.pck")
        return commandLine
    }

    override fun getGodotAppLayout(): Int = R.layout.activity_main

    override fun getHostPlugins(godot: Godot): Set<GodotPlugin> {
        AndroidBridgePlugin.ensureRegistered(godot)
        return setOfNotNull(AndroidBridgePlugin.getInstance())
    }

    override fun onGodotSetupCompleted() {
        super.onGodotSetupCompleted()

        // ↓↓↓ 这里就是"Android 业务代码"的位置(用 Toast 演示)↓↓↓
        runOnUiThread {
            findViewById<Button>(R.id.android_button).setOnClickListener {
                val time = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
                pushAndroidMessage("Android 业务代码被调用 @ $time")
            }

            // 业务入口示例:外部 Intent 也能触发业务(如点击通知跳转的场景)。
            // 测试:adb shell am start -n com.acorn.godot.communication/.MainActivity \
            //   --es push_message "来自 Intent 的业务触发"
            intent?.getStringExtra(EXTRA_PUSH_MESSAGE)?.let { pushAndroidMessage(it) }
        }
    }

    private fun pushAndroidMessage(message: String) {
        // Android → Godot:发信号,Godot 场景里会收到并做出反应
        AndroidBridgePlugin.getInstance()?.pushMessageToGodot(message)
    }

    companion object {
        const val EXTRA_PUSH_MESSAGE = "push_message"
    }
}

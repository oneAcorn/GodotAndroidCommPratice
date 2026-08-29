extends Node3D
## 主场景:展示 3 个模型 + 演示 Godot ⇄ Android 双向通信。
##
## 整个场景在代码里搭建(便于阅读每一部分),模型点击用物理射线拾取。
## 通信全部经由自动加载单例 AndroidBridge(scripts/android_bridge.gd)。

const MODELS := {
	"铁砧 anvil": {
		"path": "res://assets/model/anvil.glb",
		"pos": Vector3(-2.2, 0.0, 0.0),
		"scale": 2.2,
	},
	"鱼骨 fish": {
		"path": "res://assets/model/cartoon_fish_bone.glb",
		"pos": Vector3(0.0, 0.0, 0.0),
		"scale": 3.0,
	},
	"木头 log": {
		"path": "res://assets/model/log_01.glb",
		"pos": Vector3(2.2, 0.0, 0.0),
		"scale": 1.4,
	},
}

const _UI_FONT_NAMES: PackedStringArray = ["sans-serif", "Roboto", "Microsoft YaHei"]

var _camera: Camera3D
var _orbit_yaw := 0.35          # 弧度
var _orbit_pitch := 0.42        # 弧度
var _orbit_distance := 6.5
var _focus := Vector3(0.0, 0.9, 0.0)

# 触摸状态:index → 当前屏幕坐标;size==1 拖动旋转,size==2 双指缩放
var _touches := {}
var _pinch_distance := 0.0

var _model_bodies := {}         # StaticBody3D.instance_id → 显示名
var _message_label: Label
var _hint_label: Label


func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_spawn_models()
	_setup_ui()

	AndroidBridge.message_from_android.connect(_on_message_from_android)
	AndroidBridge.toast_shown.connect(_on_toast_shown)

	print("[Main] Godot 场景就绪, Android 插件可用: %s" % AndroidBridge.is_android_available())
	# Godot → Android:同步调用,直接拿返回值(桌面模拟模式返回占位文本)
	_hint_label.text = "设备: %s" % AndroidBridge.get_device_info()

	# 启动自检:3 秒后自动走一次 Godot → Android 的调用(Toast),
	# Android 弹完会回发 toast_shown,消息标签即显示回执。
	var self_test := get_tree().create_timer(3.0)
	self_test.timeout.connect(func() -> void:
		print("[Main] 启动自检:调用 Android show_toast")
		AndroidBridge.show_toast("启动自检:Godot → Android 通信正常!")
	)


# ---------------------------------------------------------------- 场景搭建

func _setup_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.42, 0.68)
	sky_material.sky_horizon_color = Color(0.68, 0.75, 0.83)
	sky_material.ground_bottom_color = Color(0.16, 0.16, 0.18)
	sky_material.ground_horizon_color = Color(0.62, 0.67, 0.72)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	# 地面:视觉网格 + 物理碰撞(平面足够大,让边缘退到地平线附近)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(300.0, 300.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.55, 0.57, 0.60)
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	add_child(ground)

	var ground_body := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 0.2, 300.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, -0.1, 0.0)
	ground_body.add_child(ground_shape)
	add_child(ground_body)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.current = true
	# 竖屏视野窄,初始拉远一点,保证三个模型都入镜
	var window_size := DisplayServer.window_get_size()
	if window_size.x < window_size.y:
		_orbit_distance = 9.5
	_update_camera_transform()


func _update_camera_transform() -> void:
	var offset := Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch)
	) * _orbit_distance
	_camera.position = _focus + offset
	_camera.look_at(_focus)


func _spawn_models() -> void:
	for display_name: String in MODELS:
		var info: Dictionary = MODELS[display_name]
		var packed: PackedScene = load(info["path"])
		if packed == null:
			push_warning("模型加载失败: %s" % info["path"])
			continue

		var body := StaticBody3D.new()
		body.position = info["pos"]
		add_child(body)

		var instance := packed.instantiate()
		instance.scale = Vector3.ONE * info["scale"]
		body.add_child(instance)

		# 用模型的实际包围盒生成碰撞体,供射线拾取
		var aabb := _compute_aabb(instance)
		if aabb.size.length() > 0.01:
			# 让模型底部贴合地面
			instance.position.y -= aabb.position.y
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = aabb.size + Vector3(0.1, 0.1, 0.1)
			collider.shape = shape
			collider.position = aabb.position + aabb.size / 2.0
			body.add_child(collider)

		_model_bodies[body.get_instance_id()] = display_name


func _compute_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_aabb: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		if first:
			result = mesh_aabb
			first = false
		else:
			result = result.merge(mesh_aabb)
	# 转回 root 局部坐标
	return AABB(result.position - root.global_position, result.size)


# ---------------------------------------------------------------- UI

func _make_ui_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = _UI_FONT_NAMES
	return font


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var font := _make_ui_font()

	var title := Label.new()
	title.text = "Godot ⇄ Android 双向通信演示"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 28.0
	title.offset_bottom = 80.0
	root.add_child(title)

	_hint_label = Label.new()
	_hint_label.text = "设备: 检测中…"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_override("font", font)
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint_label.offset_top = 84.0
	_hint_label.offset_bottom = 112.0
	root.add_child(_hint_label)

	_message_label = Label.new()
	_message_label.text = "Android 消息: 等待中…"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_override("font", font)
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_message_label.add_theme_constant_override("shadow_offset_y", 2)
	_message_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# 注意避让:Android 侧按钮(layout/activity_main.xml)占屏幕底部约 72dp
	_message_label.offset_top = -250.0
	_message_label.offset_bottom = -218.0
	root.add_child(_message_label)

	var toast_button := Button.new()
	toast_button.text = "调用 Android Toast"
	toast_button.add_theme_font_override("font", font)
	toast_button.add_theme_font_size_override("font_size", 22)
	toast_button.pressed.connect(_on_toast_button_pressed)
	toast_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# 锚点定位:相对底部中心的偏移,横竖屏都成立
	toast_button.offset_left = -140.0
	toast_button.offset_right = 140.0
	toast_button.offset_top = -312.0
	toast_button.offset_bottom = -256.0
	root.add_child(toast_button)


func _on_toast_button_pressed() -> void:
	# Godot → Android:发出调用,Android 弹 Toast 后会回发 toast_shown
	AndroidBridge.show_toast("你好 Android!这条消息来自 Godot 场景。")


# ---------------------------------------------------------------- 输入(旋转/缩放/拾取)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
			var picked := _pick_model(touch.position)
			if picked != "":
				_on_model_clicked(picked)
			if _touches.size() == 2:
				_pinch_distance = _current_pinch_distance()
		else:
			_touches.erase(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = drag.position
		if _touches.size() == 1:
			_orbit_yaw -= drag.relative.x * 0.008
			_orbit_pitch = clampf(_orbit_pitch + drag.relative.y * 0.006, 0.05, 1.35)
			_update_camera_transform()
		elif _touches.size() == 2:
			var new_distance := _current_pinch_distance()
			if _pinch_distance > 0.0:
				_orbit_distance = clampf(
					_orbit_distance * _pinch_distance / new_distance, 3.0, 14.0
				)
				_update_camera_transform()
			_pinch_distance = new_distance
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance - 0.5, 3.0, 14.0)
			_update_camera_transform()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance + 0.5, 3.0, 14.0)
			_update_camera_transform()


func _current_pinch_distance() -> float:
	var positions := _touches.values()
	if positions.size() < 2:
		return 0.0
	return (positions[0] as Vector2).distance_to(positions[1] as Vector2)


func _pick_model(screen_pos: Vector2) -> String:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider: Object = hit["collider"]
	return _model_bodies.get(collider.get_instance_id(), "")


func _on_model_clicked(display_name: String) -> void:
	# 本地反馈:让被点击的模型转一圈
	for body_id: int in _model_bodies:
		if _model_bodies[body_id] == display_name:
			var body := instance_from_id(body_id) as Node3D
			if body:
				body.set_meta("spinning", true)
				var tween := create_tween()
				tween.tween_property(body, "rotation:y", body.rotation.y + TAU, 1.0) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				tween.finished.connect(func() -> void: body.remove_meta("spinning"))
			break

	# Godot → Android:交给业务层处理
	AndroidBridge.notify_model_clicked(display_name)


# ---------------------------------------------------------------- Android → Godot

func _on_message_from_android(text: String) -> void:
	_message_label.text = "Android 消息: %s" % text
	print("[Main] 收到 Android 消息: %s" % text)
	_hop_all_models()


func _on_toast_shown(text: String) -> void:
	_message_label.text = "Android 已弹出 Toast ✓ (%s)" % text
	print("[Main] Android Toast 回执: %s" % text)


## 收到 Android 消息时,让所有模型跳一下作为视觉反馈
func _hop_all_models() -> void:
	for body_id: int in _model_bodies:
		var body := instance_from_id(body_id) as Node3D
		if body == null:
			continue
		var base_y := body.position.y
		var tween := create_tween()
		tween.tween_property(body, "position:y", base_y + 0.5, 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(body, "position:y", base_y, 0.26) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	# 缓慢自转,让画面在静止时也有生命感(点击动画期间暂停,避免打架)
	for body_id: int in _model_bodies:
		var body := instance_from_id(body_id) as Node3D
		if body and not body.has_meta("spinning"):
			body.rotation.y += _delta * 0.25

extends Node3D
## Start screen: Knife Cell Striker at dusk, Iron Wake story, roster, begin tutorial.

signal start_requested

var cam: Camera3D
var t := 0.0
var controls_box: Control
var story_box: Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(Mission.make_environment())
	add_child(Mission.make_sun())
	_backdrop()
	_ui()

func _backdrop() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/terrain.gdshader")
	ground.material_override = gm
	add_child(ground)
	var mech := Mech.build_model(Color("ff2a3a"))
	mech.rotation.y = -0.6
	add_child(mech)
	var pose := {"hip_L": Vector3(-0.1, 0, 0.05), "hip_R": Vector3(-0.42, 0, -0.05), "knee_L": Vector3(0.45, 0, 0),
		"knee_R": Vector3(0.75, 0, 0), "ankle_L": Vector3(-0.35, 0, -0.05), "ankle_R": Vector3(-0.33, 0, 0.05),
		"torso": Vector3(0.05, -0.25, 0), "shoulder_R": Vector3(-0.15, 0, 0)}
	for k in pose:
		var n := mech.find_child(k, true, false) as Node3D
		if n:
			n.rotation = pose[k]
	var pel := mech.find_child("pelvis", true, false) as Node3D
	if pel:
		pel.position.y = 5.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rock := Terrain.rock_mesh(3, 1)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("5e4538")
	rm.roughness = 0.95
	for i in 26:
		var r := MeshInstance3D.new()
		r.mesh = rock
		r.material_override = rm
		var a := rng.randf() * TAU
		var d := rng.randf_range(14.0, 120.0)
		var s := rng.randf_range(0.6, 5.0)
		r.position = Vector3(cos(a) * d, -s * 0.2, sin(a) * d)
		r.scale = Vector3(s * 1.3, s, s)
		r.rotation.y = rng.randf() * TAU
		add_child(r)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

func _process(delta: float) -> void:
	t += delta
	var a := 2.35 + sin(t * 0.07) * 0.35
	cam.position = Vector3(cos(a) * 24.0, 5.5 + sin(t * 0.11) * 0.6, sin(a) * 24.0)
	cam.look_at(Vector3(-4.0, 6.0, 0.0), Vector3.UP)
	cam.h_offset = -4.5

func _lbl(text: String, size: int, col: Color, font: Font, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_override("font", Game.font_mono)
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("c8102e") if primary else Color(0.1, 0.1, 0.11, 0.85)
	sb.content_margin_left = 20
	sb.border_color = Color("ff4a5a")
	sb.border_width_left = 0 if primary else 3
	var sh := sb.duplicate()
	sh.bg_color = Color("e0223f") if primary else Color(0.2, 0.08, 0.09, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("focus", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_color_override("font_color", Color("f4efe4"))
	return b

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.04, 0.05, 0.94))
	g.set_color(1, Color(0.04, 0.04, 0.05, 0.0))
	g.add_point(0.55, Color(0.04, 0.04, 0.05, 0.8))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 1000
	layer.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_right = 700
	for side in ["left", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64 if side == "left" else 44)
	layer.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)
	var bone := Color("e9e4d6")
	var dim := Color(0.91, 0.89, 0.84, 0.62)
	col.add_child(_lbl("A HUNDRED YEARS UNDER ARMS", 13, Color("ff4a5a"), Game.font_mono))
	col.add_child(_lbl("IRON WAKE", 120, bone, Game.font_display))
	col.add_child(_lbl("STEEL PEOPLE.  HARDER GROUND.  FURTHER TOMORROW.", 13, dim, Game.font_mono))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	story_box = VBoxContainer.new()
	story_box.add_theme_constant_override("separation", 10)
	for para in Game.STORY:
		story_box.add_child(_lbl(para, 17, bone, Game.font_body, true))
	var roster := GridContainer.new()
	roster.columns = 3
	roster.add_theme_constant_override("h_separation", 22)
	roster.add_theme_constant_override("v_separation", 6)
	for r in Game.ROSTER:
		roster.add_child(_lbl(r["callsign"], 14, r["color"], Game.font_mono))
		roster.add_child(_lbl(r["name"], 14, bone, Game.font_body))
		roster.add_child(_lbl(r["role"], 14, dim, Game.font_body))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	story_box.add_child(gap2)
	story_box.add_child(_lbl("THE LANCE", 12, dim, Game.font_mono))
	story_box.add_child(roster)
	col.add_child(story_box)
	controls_box = VBoxContainer.new()
	controls_box.visible = false
	var rows := [["W / S · WHEEL", "Throttle up and down. It holds where you leave it. X is all stop."],
		["A / D", "Turn the legs."], ["MOUSE", "Twist and pitch the torso. No lock-on: line up the shot."],
		["C", "Centre the torso over the legs."], ["SPACE / L-MOUSE", "Chain fire: RAC burst, laser, SRMs, in order."],
		["TAB", "Tac map. Time slows. Assign lancemates to drones."], ["ESC", "Pause."]]
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 24)
	cg.add_theme_constant_override("v_separation", 8)
	for r in rows:
		cg.add_child(_lbl(r[0], 14, Color("5fd8ff"), Game.font_mono))
		cg.add_child(_lbl(r[1], 16, bone, Game.font_body))
	controls_box.add_child(cg)
	col.add_child(controls_box)
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap3)
	var start := _btn("BEGIN  ·  OPERATION DRY WASH  (TUTORIAL)", true)
	start.pressed.connect(func():
		Sfx.play("select", -4.0)
		start_requested.emit())
	col.add_child(start)
	var ctl := _btn("CONTROLS", false)
	ctl.pressed.connect(func():
		Sfx.play("ui", -6.0)
		controls_box.visible = not controls_box.visible
		story_box.visible = not controls_box.visible
		ctl.text = "STORY" if controls_box.visible else "CONTROLS")
	col.add_child(ctl)
	start.grab_focus.call_deferred()

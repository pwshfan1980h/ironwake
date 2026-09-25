class_name Mission
extends Node3D
## Tutorial: Operation Dry Wash. Intro film -> dropship drop -> patrol, drone kill, evasion drill,
## tac-map targeting, drone wave, extraction. Played first person from the Striker's cockpit.

signal restart
signal quit_to_title

const DROPSHIP := preload("res://assets/mechs/dropship.glb")
const VIDEO_PATH := "res://assets/video/dropship_intro.ogv"
const ROUTE: Array[Vector2] = [Vector2(0, 250), Vector2(50, 150), Vector2(-20, 30), Vector2(40, -110), Vector2(0, -230)]
const ROUTE_NAMES := ["LZ", "NAV ALPHA", "NAV BRAVO", "NAV CHARLIE", "NAV DELTA"]
const DERELICT := Vector3(-14, 0, 100)
const LANCE := [["ANVIL", Vector3(-16, 0, 12)], ["KESTREL", Vector3(16, 0, 12)], ["RATCHET", Vector3(0, 0, 26)]]

var route_points: Array[Vector2] = ROUTE
var route_names := ROUTE_NAMES
var terrain: Terrain
var fx: Fx
var projectiles: Projectiles
var hud: Hud
var tacmap: TacMap
var player: Mech
var lance: Array[Mech] = []
var drones: Array[Drone] = []
var cam: Camera3D
var cockpit: Cockpit
var cam_yaw := 0.0      # torso heading, for the compass
var cam_pitch := -0.12  # torso pitch
var want_twist := 0.0   # torso twist the mouse asks for; the torso slews toward it
var clock := 0.0
var waypoint = null
var waypoint_name := ""
var waypoint_index := -1
var stats := {"shots": 0, "hits": 0, "evaded": 0, "close": 0, "taken": 0.0, "kills": 0, "lance_kills": 0, "time": 0.0}
var state := "loading"
var step := ""
var step_t := 0.0
var flags := {}
var drill_evades := 0
var drill_drone: Drone
var wave: Array[Drone] = []
var shake_amt := 0.0
var fov_kick := 0.0
var slowmo_until := 0
var last_incoming := -99.0
var ship: Node3D
var ship_pv := {}
var ship_t := 0.0
var ship_mode := ""
var fall_v := 0.0
var landed_t := -1.0
var marker: Node3D
var ui: CanvasLayer
var overlay: Control
var loading: Label
var skip_intro := false
var autopilot := false   # debug bot: plays the tutorial (see _bot_input)

func _ready() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	loading = _label("LOADING HARROW BASIN…", 18, Color("e9e4d6"))
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bg := ColorRect.new()
	bg.color = Color("0d0e10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	ui.add_child(loading)
	loading.set_meta("bg", bg)
	_build.call_deferred()

func _label(text: String, size: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else Game.font_mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

# ---------------------------------------------------------------- world
static func make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("1b2236")
	psm.sky_horizon_color = Color("c2825e")
	psm.sky_curve = 0.09
	psm.ground_horizon_color = Color("8a5f48")
	psm.ground_bottom_color = Color("2a2220")
	psm.sun_angle_max = 18.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("9a6e58")
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	return we

static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffb27e")
	sun.light_energy = 1.7
	sun.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(-140.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	return sun

func _build() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	add_child(make_environment())
	add_child(make_sun())
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(ROUTE)
	fx = Fx.new()
	add_child(fx)
	projectiles = Projectiles.new()
	add_child(projectiles)
	projectiles.setup(self)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.03
	cam.far = 1600.0
	add_child(cam)
	cam.current = true
	_build_marker()
	_build_derelict()
	_build_dust()
	var lz := _ground(Vector3(ROUTE[0].x, 0, ROUTE[0].y))
	player = Mech.new()
	add_child(player)
	player.setup(self, "GIDEON", Color("ff2a3a"), true)
	player.position = lz
	for spec in LANCE:
		var m := Mech.new()
		add_child(m)
		m.setup(self, spec[0], Game.color_of(spec[0]), false)
		m.formation = spec[1]
		m.position = _ground(lz + spec[1] + Vector3(0, 0, -14))
		m.aim_yaw = 0.0
		lance.append(m)
	cockpit = Cockpit.new()
	add_child(cockpit)
	cockpit.setup(self, cam)
	_build_ship()
	hud = Hud.mount(ui, self)
	tacmap = TacMap.new()
	ui.add_child(tacmap)
	tacmap.setup(self)
	loading.get_meta("bg").queue_free()
	loading.queue_free()
	if skip_intro:
		_start_drop(true)
	else:
		_play_video()

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.sample(p.x, p.z), p.z)

func _build_marker() -> void:
	marker = Node3D.new()
	add_child(marker)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.37, 0.85, 1.0, 0.22)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 2.2
	cm.height = 160.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = mat
	beam.position.y = 80.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 17.0
	tm.outer_radius = 18.0
	ring.mesh = tm
	var rm := mat.duplicate()
	rm.albedo_color = Color(0.37, 0.85, 1.0, 0.5)
	ring.material_override = rm
	ring.position.y = 0.4
	marker.add_child(ring)
	marker.visible = false

func _build_derelict() -> void:
	var hull := Mech.build_model(Color.BLACK, true)
	var p := _ground(DERELICT)
	hull.position = p + Vector3(0, -2.6, 0)
	hull.rotation = Vector3(0.35, 2.2, 0.55)
	add_child(hull)
	terrain.obstacles.append(Vector4(p.x, p.z, 4.5, p.y + 8.0))

func _build_dust() -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.85, 0.7, 0.35)
	q.material = mat
	p.mesh = q
	p.amount = 260
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(60, 14, 60)
	p.direction = Vector3(1, 0.05, 0.3)
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.name = "AirDust"
	add_child(p)

func _build_ship() -> void:
	ship = Node3D.new()
	add_child(ship)
	var model: Node3D = DROPSHIP.instantiate()
	model.rotation.y = PI
	ship.add_child(model)
	var mats := Mech.make_mats(Color("ff2a3a"), false)
	var thrust := StandardMaterial3D.new()
	thrust.albedo_color = Color.BLACK
	thrust.emission_enabled = true
	thrust.emission = Color("ffb070")
	thrust.emission_energy_multiplier = 6.0
	mats["THRUST"] = thrust
	Mech.apply_mats(model, mats)
	for n in ["engine_FL", "engine_FR", "engine_RL", "engine_RR", "mech_mount"]:
		ship_pv[n] = model.find_child(n, true, false)
	var l := OmniLight3D.new()
	l.light_color = Color("ffb070")
	l.light_energy = 3.0
	l.omni_range = 40.0
	l.position = Vector3(0, -6, 0)
	ship.add_child(l)
	ship.visible = false

# ---------------------------------------------------------------- intro film
func _play_video() -> void:
	state = "video"
	if not ResourceLoader.exists(VIDEO_PATH):
		_start_drop(false)
		return
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var vp := VideoStreamPlayer.new()
	vp.stream = load(VIDEO_PATH)
	vp.expand = true
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(vp)
	var card := VBoxContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.position = Vector2(56, -170)
	card.add_child(_label("IRON WAKE · HARROW BASIN · 18:42 LOCAL", 14, Color("e9e4d6")))
	card.add_child(_label("OPERATION DRY WASH", 54, Color("e9e4d6"), Game.font_display))
	card.modulate.a = 0.0
	overlay.add_child(card)
	var skip := _label("SPACE / ENTER TO SKIP", 12, Color(0.91, 0.89, 0.84, 0.5))
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-240, -44)
	overlay.add_child(skip)
	ui.add_child(overlay)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(card, "modulate:a", 1.0, 0.8)
	tw.tween_interval(3.5)
	tw.tween_property(card, "modulate:a", 0.0, 0.8)
	vp.finished.connect(_end_video)
	vp.play()

func _end_video() -> void:
	if state != "video":
		return
	if overlay:
		overlay.queue_free()
		overlay = null
	_start_drop(false)

# ---------------------------------------------------------------- drop sequence
func _start_drop(instant: bool) -> void:
	state = "drop"
	player.frozen = true
	hud.show_combat = false
	ship.visible = true
	ship_mode = "in"
	ship_t = 0.0
	if instant:
		ship_t = 8.9
		hud.link = 0.5
	else:
		hud.radio("drop_01")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _ship_path(t: float) -> void:
	var lz := _ground(Vector3(ROUTE[0].x, 0, ROUTE[0].y))
	var hover := lz + Vector3(0, 30.0, -0.5)
	var start := lz + Vector3(-70, 75, 270)
	var k := clampf(t / 7.0, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	ship.position = start.lerp(hover, e) + Vector3(0, sin(t * 1.3) * 0.4 * k, 0)
	ship.rotation = Vector3(smoothstep(0.55, 0.85, k) * (1.0 - smoothstep(0.9, 1.0, k)) * 0.22, 0.0, -0.3 * (1.0 - e))
	var tilt := lerpf(0.9, 0.0, smoothstep(0.25, 0.9, k))
	for n in ["engine_FL", "engine_FR", "engine_RL", "engine_RR"]:
		ship_pv[n].rotation.x = tilt

func _tick_ship(delta: float) -> void:
	if not ship.visible:
		return
	ship_t += delta
	if ship_mode == "in":
		_ship_path(ship_t)
		if ship_t > 4.5 and fmod(ship_t, 0.4) < delta:
			fx.big_dust(_ground(ship.position))
		if player.frozen and landed_t < 0.0:
			if ship_t < 9.0:
				player.position = ship_pv["mech_mount"].global_position
				player.yaw = ship.rotation.y
				player.rotation.y = player.yaw
			if ship_t > 7.6 and not flags.get("mark", false):
				flags["mark"] = true
				hud.radio("drop_02")
		if ship_t >= 9.0 and landed_t < 0.0:
			if fall_v == 0.0:
				Sfx.play("release", 0.0, 0.6)   # clamps let go
				cockpit.impact(0.5)
			fall_v += 26.0 * delta
			player.position.y -= fall_v * delta
			var g := terrain.sample(player.position.x, player.position.z)
			if player.position.y <= g:
				player.position.y = g
				_landed()
		if ship_t > 11.0:
			ship_mode = "out"
			ship_t = 0.0
	elif ship_mode == "out":
		var v := Vector3(0.35, 0.3, -1.0).normalized() * (8.0 + ship_t * 14.0)
		ship.position += v * delta
		ship.rotation.x = lerpf(ship.rotation.x, -0.12, delta)
		for n in ["engine_FL", "engine_FR", "engine_RL", "engine_RR"]:
			ship_pv[n].rotation.x = lerpf(ship_pv[n].rotation.x, 0.8, delta)
		if ship_t > 14.0:
			ship.visible = false
	elif ship_mode == "pickup":
		var dz := _ground(Vector3(ROUTE[4].x, 0, ROUTE[4].y))
		var hover := dz + Vector3(0, 34.0, 0)
		var start := dz + Vector3(60, 80, -260)
		var k := clampf(ship_t / 7.0, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		ship.position = start.lerp(hover, e)
		ship.rotation = Vector3(0.0, PI, 0.3 * (1.0 - e))
		for n in ["engine_FL", "engine_FR", "engine_RL", "engine_RR"]:
			ship_pv[n].rotation.x = lerpf(0.9, 0.0, smoothstep(0.25, 0.9, k))

func _landed() -> void:
	landed_t = clock
	player.land_crouch = 1.3
	fx.big_dust(player.position)
	fx.big_dust(player.position + Vector3(4, 0, 2))
	shake(1.0)
	cockpit.impact(2.2)
	hud.glitch(0.8)
	Sfx.play("land", 2.0)
	get_tree().create_timer(0.9, false).timeout.connect(func(): hud.radio("drop_03"))

# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if state == "loading" or state == "ended_idle":
		return
	clock += delta
	if Time.get_ticks_msec() < slowmo_until:
		Engine.time_scale = 0.35
	elif not tacmap.visible and Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	if state == "video":
		return
	_tick_ship(delta)
	if state == "play":
		stats["time"] += delta
		if autopilot:
			_bot_input(delta)
		else:
			_player_input()
		_tick_step(delta)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not tacmap.visible and overlay == null:
			_show_pause()
	elif state == "drop":
		player.throttle = 0.0
		player.turn = 0.0
		player.trigger = false
		if landed_t < 0.0:
			hud.link = minf(0.5, hud.link + delta * 0.06)
		else:
			hud.link = minf(1.0, hud.link + delta * 0.45)
		cockpit.boot = clampf((clock - landed_t) / 1.4, 0.0, 1.0) if landed_t >= 0.0 else 0.0
		if landed_t >= 0.0 and clock - landed_t > 1.6:
			_begin_play()
	for m in lance:
		m.ai_tick(player)
		m.update(delta)
	if state == "play" or state == "failing":
		player.slew_torso(want_twist, delta)
	player.update(delta)
	for i in range(drones.size() - 1, -1, -1):
		var d := drones[i]
		if not is_instance_valid(d):
			drones.remove_at(i)
			continue
		d.tick(delta)
	_update_camera(delta)
	cockpit.update(delta)
	var dust := get_node_or_null("AirDust") as CPUParticles3D
	if dust:
		dust.global_position = player.position + Vector3(0, 8, 0)
	if waypoint != null:
		marker.visible = true
		marker.position = waypoint
		marker.rotation.y += delta * 0.4

func _begin_play() -> void:
	state = "play"
	player.frozen = false
	hud.show_combat = true
	hud.link = 1.0
	cockpit.boot = 1.0
	_set_step("nav_alpha")

func _player_input() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not tacmap.visible
	var delta := get_process_delta_time()
	# throttle: hold W / S to move the lever; it stops at the zero detent before going into reverse
	var ti := Input.get_axis("throttle_down", "throttle_up")
	if ti != 0.0:
		var nt := clampf(player.throttle + ti * 0.75 * delta, -1.0, 1.0)
		var just := Input.is_action_just_pressed("throttle_up") or Input.is_action_just_pressed("throttle_down")
		if player.throttle != 0.0 and signf(nt) != signf(player.throttle) and not just:
			nt = 0.0
		player.throttle = nt
	if Input.is_action_just_pressed("all_stop"):
		player.throttle = 0.0
	player.turn = Input.get_axis("turn_right", "turn_left")
	if Input.is_action_pressed("center_torso"):
		want_twist = move_toward(want_twist, 0.0, Mech.TWIST_RATE * delta)
	cockpit.stick_input(Vector2(-player.turn, 0.0) * 0.6)
	player.trigger = captured and Input.is_action_pressed("fire")

func _bot_input(_delta: float) -> void:
	var goal = waypoint
	var shoot: Drone = null
	var best := 170.0
	for d in drones:
		if is_instance_valid(d) and d.alive and not d.invulnerable and d.position.distance_to(player.position) < best:
			best = d.position.distance_to(player.position)
			shoot = d
	if step == "drill" and drill_drone:
		goal = drill_drone.position
	if shoot:
		goal = shoot.position
	if step == "tacmap" and lance[0].ai_target == null:
		for d in wave:
			if is_instance_valid(d) and d.alive:
				assign(lance[0], d)
				break
	if goal == null:
		player.throttle = 0.0
		player.turn = 0.0
		return
	var to: Vector3 = goal - player.position
	var flat := Vector2(to.x, to.z).length()
	var bearing := atan2(-to.x, -to.z)
	# torso tracks the goal; legs walk toward it, or cross its line of fire when close
	want_twist = clampf(wrapf(bearing - player.yaw, -PI, PI), -Mech.TWIST_MAX, Mech.TWIST_MAX)
	var leg_goal := bearing
	var thr := 1.0
	if step == "drill" and flat < 120.0:
		# cross its line of fire; turn about when a boulder or slope stops the legs
		if absf(player.speed) < 1.0 and step_t - float(flags.get("bot_flip_t", -9.0)) > 4.0:
			flags["bot_flip_t"] = step_t
			flags["bot_side"] = -float(flags.get("bot_side", 1.0))
		leg_goal = bearing + PI * 0.5 * float(flags.get("bot_side", 1.0))
		thr = 0.8
	elif shoot and flat < 60.0:
		leg_goal = bearing + PI * 0.5
		thr = 0.5
	elif not shoot and flat < 8.0:
		thr = 0.0
	player.turn = clampf(wrapf(leg_goal - player.yaw, -PI, PI) * 2.0, -1.0, 1.0)
	player.throttle = thr
	var chest := player.position + Vector3(0, 9.0, 0)
	cam_pitch = clampf(asin(clampf((goal - chest).normalized().y, -1.0, 1.0)), Mech.PITCH_MIN, Mech.PITCH_MAX) if shoot else -0.1
	player.trigger = shoot != null and absf(wrapf(bearing - player.aim_yaw, -PI, PI)) < 0.12

func _update_camera(delta: float) -> void:
	# the cockpit rides the torso: legs heading + twist, torso pitch, a little of the pelvis roll
	if state != "play" and state != "failing":
		want_twist = 0.0
		player.twist = 0.0
		player.aim_yaw = player.yaw
		cam_pitch = -0.08
	var pel: Node3D = player.pv["pelvis"]
	var b := Basis(Vector3.UP, player.aim_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Basis(Vector3.BACK, pel.rotation.z * 0.4)
	cockpit.global_transform = Transform3D(b, player.pv["cockpit_cam"].global_position)
	cam_yaw = player.aim_yaw
	player.aim_pitch = cam_pitch
	# aim: ray from the eye through the reticle
	var d := -b.z
	var hit := raycast(cockpit.global_position + d * 3.0, d, 900.0)
	player.aim_point = hit["pos"]
	shake_amt = maxf(0.0, shake_amt - delta * 2.5)
	var s := shake_amt * shake_amt
	cam.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s * 0.02
	fov_kick = lerpf(fov_kick, 0.0, 1.0 - exp(-5.0 * delta))
	cam.fov = 72.0 + fov_kick

func _unhandled_input(e: InputEvent) -> void:
	if state == "video":
		if e.is_action_pressed("skip") or (e is InputEventMouseButton and e.pressed):
			var vp := overlay.find_children("*", "VideoStreamPlayer", true, false)
			if vp.size() > 0:
				(vp[0] as VideoStreamPlayer).stop()
			_end_video()
		return
	if state != "play" and state != "drop":
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and state == "play":
		want_twist = clampf(want_twist - e.relative.x * 0.0022, -Mech.TWIST_MAX, Mech.TWIST_MAX)
		cam_pitch = clampf(cam_pitch - e.relative.y * 0.0018, Mech.PITCH_MIN, Mech.PITCH_MAX)
		cockpit.stick_input(Vector2(-e.relative.x, -e.relative.y) * 0.05)
	elif e is InputEventMouseButton and e.pressed and state == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var k := 0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
		player.throttle = clampf(snappedf(player.throttle + k, 0.1), -1.0, 1.0)
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not tacmap.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("map") and state == "play":
		if tacmap.visible:
			tacmap.close()
		else:
			tacmap.open()
			flags["map_opened"] = true
	elif e.is_action_pressed("pause"):
		if tacmap.visible:
			tacmap.close()
		else:
			_show_pause()
	elif tacmap.visible:
		for i in 3:
			if e.is_action_pressed("select_%d" % (i + 1)):
				tacmap.select_index(i)

# ---------------------------------------------------------------- world queries
func listener() -> Vector3:
	return cam.global_position if cam else Vector3.ZERO

func shake(k: float) -> void:
	shake_amt = maxf(shake_amt, k)

func footfall(a: float) -> void:
	cockpit.footfall(a)
	shake(0.12 * a)

func resolve_move(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var p := to
	for o in terrain.obstacles:
		var dx := p.x - o.x
		var dz := p.z - o.y
		var rr := o.z + radius
		var d2 := dx * dx + dz * dz
		if d2 < rr * rr and d2 > 0.0001:
			var d := sqrt(d2)
			p.x = o.x + dx / d * rr
			p.z = o.y + dz / d * rr
	var h0 := terrain.sample(from.x, from.z)
	var run := Vector2(p.x - from.x, p.z - from.z).length()
	if run > 0.0001 and (terrain.sample(p.x, p.z) - h0) / run > 0.85:
		var px := Vector3(p.x, 0.0, from.z)
		var pz := Vector3(from.x, 0.0, p.z)
		if absf(p.x - from.x) > 0.0001 and (terrain.sample(px.x, px.z) - h0) / absf(p.x - from.x) <= 0.85:
			p = px
		elif absf(p.z - from.z) > 0.0001 and (terrain.sample(pz.x, pz.z) - h0) / absf(p.z - from.z) <= 0.85:
			p = pz
		else:
			p = Vector3(from.x, 0.0, from.z)
	var lim := Terrain.SIZE * 0.45
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	p.y = terrain.sample(p.x, p.z)
	return p

func raycast(origin: Vector3, dir: Vector3, max_d: float, ignore_drones := false) -> Dictionary:
	var best := max_d
	var hit_drone: Drone = null
	if not ignore_drones:
		for d in drones:
			if not is_instance_valid(d) or not d.alive:
				continue
			var oc := origin - d.position
			var b := oc.dot(dir)
			var c := oc.dot(oc) - Drone.RADIUS * Drone.RADIUS
			var disc := b * b - c
			if disc >= 0.0:
				var tt := -b - sqrt(disc)
				if tt > 0.0 and tt < best:
					best = tt
					hit_drone = d
	# boulders, hoodoos, derelict: vertical cylinders
	var d2 := Vector2(dir.x, dir.z)
	var l2 := d2.length_squared()
	if l2 > 1e-6:
		for o in terrain.obstacles:
			var oc2 := Vector2(origin.x - o.x, origin.z - o.y)
			var b2 := oc2.dot(d2)
			var c2 := oc2.dot(oc2) - o.z * o.z
			var disc2 := b2 * b2 - l2 * c2
			if disc2 >= 0.0:
				var tt := (-b2 - sqrt(disc2)) / l2
				if tt > 0.0 and tt < best and origin.y + dir.y * tt < o.w:
					best = tt
					hit_drone = null
	# terrain march
	var tt3 := 0.0
	var stepl := 1.5
	while tt3 < best:
		var nt := minf(tt3 + stepl, best)
		var q := origin + dir * nt
		if q.y < terrain.sample(q.x, q.z):
			var lo := tt3
			var hi := nt
			for k in 7:
				var mid := (lo + hi) * 0.5
				var m := origin + dir * mid
				if m.y < terrain.sample(m.x, m.z):
					hi = mid
				else:
					lo = mid
			best = hi
			hit_drone = null
			break
		tt3 = nt
		stepl = minf(stepl * 1.04 + 0.05, 6.0)
	return {"pos": origin + dir * best, "drone": hit_drone, "dist": best}

func has_los(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var hit := raycast(a, d.normalized(), d.length(), true)
	return hit["dist"] >= d.length() - 1.0

func spawn_sabot(from: Vector3, to: Vector3, speed: float, dmg: float, drill: bool) -> void:
	projectiles.spawn_sabot(from, to, speed, dmg, drill)
	if clock - last_incoming > 6.0:
		last_incoming = clock
		hud.radio("sys_incoming")

func spawn_missile(from: Vector3, dir: Vector3, owner: Node) -> void:
	projectiles.spawn_missile(from, dir, owner)

func splash(at: Vector3, radius: float, dmg: float, owner: Node) -> void:
	for d in drones:
		if is_instance_valid(d) and d.alive:
			var dist := d.position.distance_to(at)
			if dist < radius + Drone.RADIUS:
				d.damage(dmg * (1.0 - 0.5 * dist / (radius + Drone.RADIUS)), owner)
				if owner == player:
					hud.hit_marker()

# ---------------------------------------------------------------- events
func assign(m: Mech, d: Drone) -> void:
	if m.ai_target != null and is_instance_valid(m.ai_target):
		m.ai_target.assigned.erase(m.callsign)
	m.ai_target = d
	if d != null:
		d.assigned.append(m.callsign)
		hud.radio("ack_" + m.callsign, true)

func on_drone_killed(d: Drone, source: Node) -> void:
	for m in lance:
		if m.ai_target == d:
			m.ai_target = null
	if source == player:
		stats["kills"] += 1
	elif source is Mech:
		stats["lance_kills"] += 1
		hud.radio("down_" + source.callsign)

func on_sabot_missed(min_d: float, drill: bool) -> void:
	# a miss counts as evaded when the legs were carrying you out of the way
	var evaded := absf(player.speed) > 4.0
	if evaded:
		stats["evaded"] += 1
	if evaded and min_d < 8.0:
		stats["close"] += 1
		slowmo_until = Time.get_ticks_msec() + 380
		hud.show_callout("CLOSE CALL")
	if drill and step == "drill" and evaded:
		drill_evades += 1
		if drill_evades == 1:
			hud.radio("drill_dodge", true)

func on_player_hit(drill: bool) -> void:
	stats["taken"] += 1
	hud.flash_damage()
	shake(0.9)
	cockpit.impact(0.8)
	Sfx.play("hit", 0.0)
	if drill and step == "drill" and clock - float(flags.get("drill_hit_t", -99.0)) > 7.0:
		flags["drill_hit_t"] = clock
		hud.radio("drill_hit")
	if player.armor < 30.0 and not flags.get("armor_warn", false):
		flags["armor_warn"] = true
		hud.radio("sys_armor")

func on_overheat() -> void:
	hud.radio("sys_heat")

func on_mech_destroyed(m: Mech) -> void:
	if m == player and state == "play":
		state = "failing"
		fx.explosion(player.position + Vector3(0, 6, 0), 1.6)
		hud.radio("fail", true)
		get_tree().create_timer(4.5, false).timeout.connect(func(): _finish(false))

# ---------------------------------------------------------------- tutorial script
func _set_waypoint(i: int) -> void:
	waypoint_index = i
	if i < 0:
		waypoint = null
		marker.visible = false
		return
	waypoint = _ground(Vector3(ROUTE[i].x, 0, ROUTE[i].y))
	waypoint_name = ROUTE_NAMES[i]

func _reached(i: int, r := 22.0) -> bool:
	return Vector2(player.position.x - ROUTE[i].x, player.position.z - ROUTE[i].y).length() < r

func _set_step(s: String) -> void:
	print("[mission] %6.1fs step -> %s  armor %d" % [stats["time"], s, int(player.armor)])
	step = s
	step_t = 0.0
	match s:
		"nav_alpha":
			_set_waypoint(1)
			hud.objective = "Walk to NAV ALPHA"
			hud.objective_hint = "W / S throttle · A / D turn the legs · mouse twists the torso"
			hud.radio("nav_01")
		"drone1":
			_set_waypoint(-1)
			_spawn_drone(Vector3(52, 0, 92), 14.0, 4.6, 7.0)
			hud.objective = "Destroy the Sable drone"
			hud.objective_hint = "Line up the reticle · hold SPACE to chain-fire"
			hud.radio("alpha_01")
			hud.radio("alpha_02")
		"nav_bravo":
			_set_waypoint(2)
			hud.objective = "Move to NAV BRAVO"
			hud.objective_hint = ""
			hud.radio("kill_first")
			hud.radio("bravo_go")
		"drill":
			_set_waypoint(-1)
			drill_drone = _spawn_drone(Vector3(-20, 0, -32), 12.0, 3.3, 4.0)
			drill_drone.invulnerable = true
			drill_drone.drill = true
			drill_drone.lead = 0.0
			drill_drone.jitter = 2.0
			drill_drone.aggro_range = 130.0
			drill_drone.cooldown = 5.0
			hud.objective = "Evade the training sabots (0/2)"
			hud.objective_hint = "Throttle up and walk across its line of fire · C centres the torso"
			hud.radio("drill_01")
			hud.radio("drill_02")
		"drill_kill":
			drill_drone.invulnerable = false
			drill_drone.fire_interval = 5.0
			hud.objective = "Destroy the drill drone"
			hud.objective_hint = "Keep your legs moving between shots"
			hud.radio("drill_done", true)
		"nav_charlie":
			_set_waypoint(3)
			for p in [Vector3(12, 0, -172), Vector3(40, 0, -188), Vector3(68, 0, -168), Vector3(52, 0, -150)]:
				var d := _spawn_drone(p, 13.0 + randf() * 5.0, 5.2, 7.0)
				d.aggro_range = 110.0
				wave.append(d)
			hud.objective = "Move to NAV CHARLIE"
			hud.objective_hint = ""
			hud.radio("charlie_go")
		"tacmap":
			_set_waypoint(-1)
			hud.objective = "Give your lance a target"
			hud.objective_hint = "TAB opens the tac map · click a lancemate, then a drone"
			hud.radio("charlie_01")
			hud.radio("charlie_02")
		"wave":
			hud.objective = "Destroy the Sable drones (0/4)"
			hud.objective_hint = "Your lance fires only on targets you assign"
		"nav_delta":
			_set_waypoint(4)
			hud.objective = "Extract at NAV DELTA"
			hud.objective_hint = ""
			hud.radio("charlie_clear")
			hud.radio("delta_go")
		"extract":
			_set_waypoint(-1)
			hud.objective = "Hold for pickup"
			ship.visible = true
			ship_mode = "pickup"
			ship_t = 0.0
			hud.radio("delta_done")

func _tick_step(delta: float) -> void:
	step_t += delta
	match step:
		"nav_alpha":
			if _reached(1):
				hud.radio("sys_waypoint")
				_set_step("drone1")
		"drone1":
			if _alive_count(drones) == 0:
				_set_step("nav_bravo")
		"nav_bravo":
			if not flags.get("derelict", false) and player.position.distance_to(_ground(DERELICT)) < 70.0:
				flags["derelict"] = true
				hud.radio("bravo_derelict")
			if _reached(2):
				hud.radio("sys_waypoint")
				_set_step("drill")
		"drill":
			hud.objective = "Evade the training sabots (%d/2)" % mini(drill_evades, 2)
			if drill_evades >= 2:
				_set_step("drill_kill")
		"drill_kill":
			if not drill_drone.alive:
				_set_step("nav_charlie")
		"nav_charlie":
			if _reached(3, 30.0):
				hud.radio("sys_waypoint")
				_set_step("tacmap")
		"tacmap":
			var assigned := false
			for m in lance:
				if m.ai_target != null:
					assigned = true
			if assigned or _alive_count(wave) < 4:
				_set_step("wave")
		"wave":
			var left := _alive_count(wave)
			hud.objective = "Destroy the Sable drones (%d/4)" % (4 - left)
			if left == 0:
				_set_step("nav_delta")
		"nav_delta":
			if _reached(4, 26.0):
				_set_step("extract")
		"extract":
			if step_t > 8.5:
				_finish(true)

func _alive_count(list: Array) -> int:
	var n := 0
	for d in list:
		if is_instance_valid(d) and d.alive:
			n += 1
	return n

func _spawn_drone(at: Vector3, alt: float, interval: float, dmg: float) -> Drone:
	var d := Drone.new()
	add_child(d)
	d.setup(self, at, alt)
	d.fire_interval = interval
	d.sabot_dmg = dmg
	drones.append(d)
	return d

# ---------------------------------------------------------------- menus
func _panel(title: String, sub: String) -> VBoxContainer:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(80, -200)
	box.add_theme_constant_override("separation", 14)
	overlay.add_child(box)
	box.add_child(_label(sub, 13, Color("ff4a5a")))
	box.add_child(_label(title, 72, Color("e9e4d6"), Game.font_display))
	ui.add_child(overlay)
	return box

func _button(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 48)
	b.add_theme_font_override("font", Game.font_mono)
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.9)
	sb.border_color = Color("ff4a5a")
	sb.border_width_left = 3
	sb.content_margin_left = 18
	var sh := sb.duplicate()
	sh.bg_color = Color(0.2, 0.08, 0.09, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("focus", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.pressed.connect(func():
		Sfx.play("select", -6.0)
		cb.call())
	box.add_child(b)
	return b

func _show_pause() -> void:
	if overlay != null or state != "play":
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var box := _panel("PAUSED", "OPERATION DRY WASH")
	var first := _button(box, "RESUME", _resume)
	_button(box, "RESTART MISSION", func():
		get_tree().paused = false
		restart.emit())
	_button(box, "QUIT TO TITLE", func():
		get_tree().paused = false
		quit_to_title.emit())
	first.grab_focus()

func _resume() -> void:
	get_tree().paused = false
	if overlay:
		overlay.queue_free()
		overlay = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _finish(success: bool) -> void:
	if state == "ended_idle":
		return
	state = "ended_idle"
	print("[mission] finished success=%s stats=%s" % [success, stats])
	Engine.time_scale = 1.0
	if tacmap.visible:
		tacmap.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_combat = false
	var box := _panel("PATROL COMPLETE" if success else "MACHINE LOST", "OPERATION DRY WASH · DEBRIEF")
	var acc := 0.0
	if stats["shots"] > 0:
		acc = 100.0 * stats["hits"] / stats["shots"]
	var rows := [
		["TIME", "%d:%02d" % [int(stats["time"]) / 60, int(stats["time"]) % 60]],
		["ACCURACY", "%d%%" % int(acc)],
		["DRONES · YOU / LANCE", "%d / %d" % [stats["kills"], stats["lance_kills"]]],
		["SABOTS EVADED", str(stats["evaded"])],
		["CLOSE CALLS", str(stats["close"])],
		["HITS TAKEN", str(int(stats["taken"]))],
		["ARMOR REMAINING", "%d%%" % int(player.armor)],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	for r in rows:
		grid.add_child(_label(r[0], 14, Color(0.91, 0.89, 0.84, 0.6)))
		grid.add_child(_label(r[1], 14, Color("e9e4d6")))
	box.add_child(grid)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)
	var first := _button(box, "REPLAY TUTORIAL" if success else "RETRY", func(): restart.emit())
	_button(box, "TITLE SCREEN", func(): quit_to_title.emit())
	first.grab_focus()

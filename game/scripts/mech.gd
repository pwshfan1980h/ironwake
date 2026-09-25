class_name Mech
extends Node3D
## Knife Cell Striker: throttle-driven legs, independent torso twist, procedural walk, chain-fire weapons.
## The same class drives the player (throttle + turn set by Mission) and lancemates (move_wish from ai_tick).

const STRIKER := preload("res://assets/mechs/striker_C.glb")
const CAMO := preload("res://shaders/camo.gdshader")
const PIVOTS := ["root", "pelvis", "torso", "hip_L", "hip_R", "knee_L", "knee_R", "ankle_L", "ankle_R",
	"shoulder_L", "shoulder_R", "elbow_L", "elbow_R", "gatling_spin", "cockpit_cam"]

const RUN := 15.0          # 54 km/h at full throttle
const BACK := 6.0          # full reverse
const ACCEL := 4.5
const BRAKE := 7.0
const TURN_RATE := 1.05    # leg turn, rad/s at a standstill
const TURN_RATE_RUN := 0.6 # leg turn at full speed
const TWIST_MAX := deg_to_rad(110.0)
const TWIST_RATE := 2.6    # torso twist, rad/s
const PITCH_MIN := -0.45
const PITCH_MAX := 0.5
const STRIDE := 5.4
const RADIUS := 2.4
const CHAIN_GAP := 0.2

var mission: Node
var callsign := "GIDEON"
var lamp := Color("ff2a3a")
var is_player := false
var model: Node3D
var pv := {}
var mats := {}

var vel := Vector3.ZERO
var move_wish := Vector3.ZERO   # AI only: desired ground velocity
var throttle := 0.0             # player: -1 (full reverse) .. 1 (full ahead)
var turn := 0.0                 # player: leg turn input -1 .. 1
var speed := 0.0                # signed speed along the legs
var twist := 0.0                # torso yaw relative to the legs
var yaw := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var aim_point := Vector3.ZERO
var phase := 0.0
var amp := 0.0
var prev_c := [1.0, 1.0]
var land_crouch := 0.0
var frozen := false
var alive := true
var armor := 100.0
var heat := 0.0
var overheat := 0.0
var trigger := false
var weapons: Array = []
var chain_index := 0
var chain_gap := 0.0
var spin := 0.0
var rac_left := 0
var rac_timer := 0.0
var flash := 0.0
var t := 0.0
var seed_f := randf() * 10.0
var ai_target: Node3D = null
var formation := Vector3.ZERO

# ---------------------------------------------------------------- model + materials
static func build_model(lamp_col: Color, derelict := false) -> Node3D:
	var m: Node3D = STRIKER.instantiate()
	var mt := make_mats(lamp_col, derelict)
	apply_mats(m, mt)
	m.set_meta("mats", mt)
	return m

static func _camo(cols: Array, cell: float, rough: float, metal: float) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = CAMO
	s.set_shader_parameter("c0", cols[0])
	s.set_shader_parameter("c1", cols[1 % cols.size()])
	s.set_shader_parameter("c2", cols[2 % cols.size()])
	s.set_shader_parameter("cell", cell)
	s.set_shader_parameter("rough", rough)
	s.set_shader_parameter("metal", metal)
	return s

static func _std(col: Color, metal: float, rough: float, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m

static func make_mats(lamp_col: Color, derelict: bool) -> Dictionary:
	if derelict:
		var rust := _camo([Color("5a3a2a"), Color("6e4a34"), Color("3e2a20")], 0.35, 0.9, 0.2)
		var dark := _std(Color("2a1f1a"), 0.3, 0.9)
		return {"ARMOR": rust, "ARMOR_ALT": rust, "FRAME": dark, "TRIM": rust, "BRASS": dark,
			"GLASS": dark, "LAMP": dark, "BARREL": dark, "DARK": dark, "DECAL": dark}
	return {
		"ARMOR": _camo([Color("2c2f33"), Color("3b3f45"), Color("1f2226")], 0.22, 0.64, 0.12),
		"ARMOR_ALT": _camo([Color("4a4f55")], 0.22, 0.56, 0.15),
		"FRAME": _camo([Color("141618")], 0.22, 0.45, 0.7),
		"TRIM": _std(lamp_col.darkened(0.15), 0.1, 0.5),
		"BRASS": _std(Color("505358"), 0.9, 0.36),
		"BARREL": _std(Color("3a3c40"), 0.95, 0.28),
		"DARK": _std(Color("0b0c0d"), 0.3, 0.85),
		"GLASS": _std(Color("050505"), 0.0, 0.1, lamp_col, 2.5),
		"LAMP": _std(Color("050505"), 0.0, 0.3, lamp_col, 5.0),
		"DECAL": _std(Color(0, 0, 0, 0), 0.0, 1.0),
	}

static func apply_mats(root: Node, mt: Dictionary) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).begins_with("DECAL"):
			mi.visible = false
			continue
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			var key: String = sm.resource_name if sm else ""
			if mt.has(key):
				mi.set_surface_override_material(i, mt[key])

func setup(m: Node, cs: String, lamp_col: Color, player: bool) -> void:
	mission = m
	callsign = cs
	lamp = lamp_col
	is_player = player
	model = build_model(lamp)
	model.rotation.y = PI
	add_child(model)
	for n in PIVOTS:
		pv[n] = model.find_child(n, true, false)
	mats = model.get_meta("mats")
	pv["torso"].rotation_order = EULER_ORDER_YXZ
	weapons = [
		{"name": "RAC/5", "cd": 0.0, "cool": 1.0, "heat": 7.0},
		{"name": "M.LASER", "cd": 0.0, "cool": 1.7, "heat": 10.0},
		{"name": "SRM-2", "cd": 0.0, "cool": 2.6, "heat": 8.0},
	]
	if is_player:
		# the pilot sits inside the torso: the cockpit replaces it for the camera
		for n in ["torso_mesh", "pelvis_mesh"]:
			var mi := model.find_child(n, true, false) as MeshInstance3D
			if mi:
				mi.visible = false

# ---------------------------------------------------------------- frame update
func update(delta: float) -> void:
	t += delta
	if not alive:
		return
	_move(delta)
	_animate(delta)
	_weapons(delta)
	heat = maxf(0.0, heat - 16.0 * delta)
	flash = maxf(0.0, flash - delta * 4.0)
	for k in ["ARMOR", "ARMOR_ALT", "FRAME"]:
		var m: ShaderMaterial = mats[k]
		m.set_shader_parameter("ground_y", position.y)
		m.set_shader_parameter("flash", flash)

func fwd_vec() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func right_of(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, -sin(a))

func _move(delta: float) -> void:
	land_crouch = maxf(0.0, land_crouch - delta * 1.6)
	if frozen:
		speed = 0.0
		vel = Vector3.ZERO
		return
	var rate := lerpf(TURN_RATE, TURN_RATE_RUN, clampf(absf(speed) / RUN, 0.0, 1.0))
	var target := 0.0
	if is_player:
		target = throttle * (RUN if throttle > 0.0 else BACK)
		yaw += turn * rate * delta
	else:
		# AI legs turn toward where they want to walk, and only walk the way they face
		var wish := Vector2(move_wish.x, move_wish.z)
		if wish.length() > 0.5:
			var diff := wrapf(atan2(-move_wish.x, -move_wish.z) - yaw, -PI, PI)
			yaw += clampf(diff, -rate * delta, rate * delta)
			target = wish.length() * maxf(0.0, cos(diff))
		else:
			var diff := wrapf(aim_yaw - yaw, -PI, PI)
			if absf(diff) > TWIST_MAX * 0.6:
				yaw += clampf(diff, -rate * delta, rate * delta)
	var speeding_up := speed == 0.0 or (signf(target) == signf(speed) and absf(target) > absf(speed))
	speed = move_toward(speed, target, (ACCEL if speeding_up else BRAKE) * delta)
	vel = fwd_vec() * speed
	var np: Vector3 = mission.resolve_move(position, position + vel * delta, RADIUS)
	var moved := Vector3(np.x - position.x, 0.0, np.z - position.z)
	if delta > 0.0 and moved.length() < (vel * delta).length() * 0.5:
		speed *= 0.5   # blocked by a wall or boulder
		vel = fwd_vec() * speed
	position = np
	rotation.y = yaw
	if not is_player:
		twist = clampf(wrapf(aim_yaw - yaw, -PI, PI), -TWIST_MAX, TWIST_MAX)

## Player torso: slew the twist toward the wanted value at the torso's rate.
func slew_torso(want_twist: float, delta: float) -> void:
	want_twist = clampf(want_twist, -TWIST_MAX, TWIST_MAX)
	twist = move_toward(twist, want_twist, TWIST_RATE * delta)
	aim_yaw = yaw + twist

func _animate(delta: float) -> void:
	var fw := fwd_vec()
	var rt := right_of(yaw)
	var vf := vel.dot(fw)
	var vs := vel.dot(rt)
	var spd := Vector2(vs, vf).length()
	amp = lerpf(amp, clampf(spd / 7.0, 0.0, 1.0), 1.0 - exp(-4.0 * delta))
	var dsgn := -1.0 if vf < -0.5 else 1.0
	phase += dsgn * delta * maxf(spd, 3.0 * amp) / (2.0 * STRIDE) * TAU
	var fwk := clampf(absf(vf) / maxf(spd, 0.01), 0.0, 1.0)
	var swk := clampf(vs / maxf(spd, 0.01), -1.0, 1.0)
	var crouch := land_crouch
	var hmax := 0.0
	var i := 0
	for side in ["L", "R"]:
		var p := phase + (0.0 if side == "L" else PI)
		var s := sin(p)
		var c := cos(p)
		var lift := maxf(0.0, c)
		var a := amp
		var hip_x := -0.26 - 0.44 * a * s * fwk - crouch * 0.28
		var hip_z := -0.2 * a * s * swk
		var knee := 0.52 + 0.1 * a + 0.95 * a * lift * lift + crouch * 0.62
		var ankle := -(hip_x + knee) + 0.1 * a * s
		pv["hip_" + side].rotation = Vector3(hip_x, 0.0, hip_z)
		pv["knee_" + side].rotation = Vector3(knee, 0.0, 0.0)
		pv["ankle_" + side].rotation = Vector3(ankle, 0.0, -hip_z)
		hmax = maxf(hmax, 2.4 * cos(hip_x) * cos(hip_z) + 2.35 * cos(hip_x + knee) + 0.55)
		if prev_c[i] > 0.0 and c <= 0.0 and a > 0.2:
			_footfall(side, a)
		prev_c[i] = c
		i += 1
	var pel: Node3D = pv["pelvis"]
	pel.position.y = hmax - 0.04 * (1.0 - amp) * (0.5 + 0.5 * sin(t * 1.4 + seed_f))
	pel.rotation.z = clampf(vs * 0.016, -0.5, 0.5) + 0.05 * amp * sin(phase)
	pel.rotation.y = 0.06 * amp * sin(phase) * fwk
	var tw := clampf(wrapf(aim_yaw - yaw, -PI, PI), -TWIST_MAX, TWIST_MAX)
	pv["torso"].rotation = Vector3(-clampf(aim_pitch, PITCH_MIN, PITCH_MAX) * 0.9, tw - pel.rotation.y, -pel.rotation.z * 0.6)
	pv["shoulder_L"].rotation.x = 0.12 * amp * sin(phase + PI) * fwk
	pv["shoulder_R"].rotation.x = 0.12 * amp * sin(phase) * fwk
	pv["gatling_spin"].rotation.z += spin * delta

func _footfall(side: String, a: float) -> void:
	var foot: Vector3 = pv["ankle_" + side].global_position
	mission.fx.dust(foot, 0.6 + a * 0.6)
	if is_player:
		Sfx.play("step", -3.0 + a * 4.0, 0.8)
		mission.footfall(a)
	else:
		Sfx.play_at("step", foot, mission.listener(), -8.0)

# ---------------------------------------------------------------- weapons (chain fire)
func _weapons(delta: float) -> void:
	for w in weapons:
		w["cd"] = maxf(0.0, w["cd"] - delta)
	chain_gap = maxf(0.0, chain_gap - delta)
	if overheat > 0.0:
		overheat -= delta
	var wants := trigger and overheat <= 0.0 and not frozen and alive
	var spin_target := 32.0 if (wants or rac_left > 0) else 0.0
	spin = move_toward(spin, spin_target, delta * (90.0 if spin_target > 0.0 else 22.0))
	if rac_left > 0:
		rac_timer -= delta
		while rac_timer <= 0.0 and rac_left > 0:
			rac_timer += 0.05
			rac_left -= 1
			_rac_round()
	if wants and chain_gap <= 0.0:
		for k in weapons.size():
			var idx := (chain_index + k) % weapons.size()
			var w: Dictionary = weapons[idx]
			if w["cd"] <= 0.0:
				_fire(idx)
				w["cd"] = w["cool"]
				heat += w["heat"]
				chain_index = (idx + 1) % weapons.size()
				chain_gap = CHAIN_GAP
				break
	if heat >= 100.0 and overheat <= 0.0:
		overheat = 2.5
		heat = 100.0
		if is_player:
			mission.on_overheat()

func _fire(idx: int) -> void:
	match idx:
		0:
			rac_left = 7
			rac_timer = 0.0
		1:
			var mz: Vector3 = pv["elbow_L"].global_transform * Vector3(0.0, -0.17, 2.55)
			var dir := (aim_point - mz).normalized()
			dir = (dir + _jitter(0.004 if is_player else 0.02)).normalized()
			var hit: Dictionary = mission.raycast(mz, dir, 650.0)
			mission.fx.beam(mz, hit["pos"], lamp)
			_apply_hit(hit, 24.0)
			_sound("laser", -4.0)
		2:
			var base: Vector3 = pv["torso"].global_transform * Vector3(-1.53, 2.85, 0.95)
			for k in 2:
				var off := Vector3(0.0, 0.25 * (k * 2 - 1), 0.0)
				var dir := (aim_point - base).normalized()
				dir = (dir + _jitter(0.01 if is_player else 0.03)).normalized()
				mission.spawn_missile(base + off, dir, self)
			_sound("srm", -4.0)

func _rac_round() -> void:
	var mz: Vector3 = pv["gatling_spin"].global_transform * Vector3(0.0, 0.0, 2.1)
	var dir := (aim_point - mz).normalized()
	dir = (dir + _jitter(0.007 if is_player else 0.025)).normalized()
	var hit: Dictionary = mission.raycast(mz, dir, 700.0)
	mission.fx.tracer(mz, hit["pos"])
	mission.fx.muzzle(mz, dir)
	_apply_hit(hit, 7.0)
	_sound("rac", -9.0)

func _apply_hit(hit: Dictionary, dmg: float) -> void:
	if is_player:
		mission.stats["shots"] += 1
	var d = hit["drone"]
	if d != null:
		d.damage(dmg, self)
		if is_player:
			mission.stats["hits"] += 1
			mission.hud.hit_marker()
	else:
		mission.fx.impact(hit["pos"])

func _sound(n: String, vol: float) -> void:
	if is_player:
		Sfx.play(n, vol)
	else:
		Sfx.play_at(n, global_position, mission.listener(), vol - 4.0)

func _jitter(s: float) -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s

func take_hit(dmg: float) -> void:
	if not alive:
		return
	armor = maxf(0.0, armor - dmg)
	flash = 1.0
	if armor <= 0.0:
		alive = false
		trigger = false
		mission.on_mech_destroyed(self)

# ---------------------------------------------------------------- lancemate AI
func ai_tick(player: Mech) -> void:
	if ai_target != null and (not is_instance_valid(ai_target) or not ai_target.alive):
		ai_target = null
	var goal: Vector3
	var chest := position + Vector3(0.0, 7.0, 0.0)
	if ai_target != null:
		var tp: Vector3 = ai_target.global_position
		var to := Vector3(tp.x - position.x, 0.0, tp.z - position.z)
		var d := to.length()
		var dirn := to / maxf(d, 0.01)
		if d > 85.0:
			goal = position + dirn * (d - 65.0)
		elif d < 38.0:
			goal = position - dirn * 12.0
		else:
			goal = position + Vector3(-dirn.z, 0.0, dirn.x) * 10.0 * sin(t * 0.5 + seed_f)
		aim_point = tp
		aim_yaw = atan2(-to.x, -to.z)
		aim_pitch = asin(clampf((tp - chest).normalized().y, -1.0, 1.0))
		var ray: Dictionary = mission.raycast(chest, (tp - chest).normalized(), (tp - chest).length() + 4.0)
		trigger = d < 140.0 and ray["drone"] == ai_target
	else:
		goal = player.position + formation.rotated(Vector3.UP, player.yaw)
		trigger = false
		aim_yaw = lerp_angle(aim_yaw, player.yaw, 0.05)
		aim_pitch = 0.0
		aim_point = chest + fwd_vec() * 200.0
	var to_goal := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	var dist := to_goal.length()
	if dist > 3.0:
		move_wish = to_goal / dist * clampf(dist * 1.1, 0.0, RUN * 0.95)
	else:
		move_wish = Vector3.ZERO

class_name Fx
extends Node3D
## Pooled tracers and beams, plus one-shot particle bursts (dust, impacts, explosions).

var _soft: GradientTexture2D
var _tracers: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _tracer_mat: StandardMaterial3D

func _ready() -> void:
	_soft = GradientTexture2D.new()
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_soft.gradient = g
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.72, 0.4) * 4.0
	for i in 48:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 0.12, 7.0)
		m.mesh = b
		m.material_override = _tracer_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_tracers.append({"node": m, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": 0.0, "len": 0.0})

func _particle_mat(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft
	return mat

func _burst(pos: Vector3, amount: int, life: float, size: float, speed: float, c0: Color, c1: Color,
		additive := false, gravity := Vector3.ZERO, spread := 180.0, dir := Vector3.UP) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_mat(additive)
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.2
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	ramp.set_color(1, c1)
	p.color_ramp = ramp
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2, false).timeout.connect(p.queue_free)

func make_trail(col: Color, size: float, smoke := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_mat(not smoke)
	p.mesh = q
	p.amount = 40
	p.lifetime = 0.6 if not smoke else 1.2
	p.local_coords = false
	p.spread = 8.0
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, 0.6, 0) if smoke else Vector3.ZERO
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 2.4 if smoke else 0.2))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.9))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	return p

func dust(pos: Vector3, k: float) -> void:
	_burst(pos + Vector3(0, 0.3, 0), 14, 1.6, 2.2 * k, 6.0 * k, Color(0.62, 0.5, 0.4, 0.55), Color(0.62, 0.5, 0.4, 0.0),
		false, Vector3(0, 0.4, 0), 80.0, Vector3.UP)

func big_dust(pos: Vector3) -> void:
	_burst(pos + Vector3(0, 0.5, 0), 40, 2.6, 5.0, 16.0, Color(0.6, 0.48, 0.38, 0.7), Color(0.6, 0.48, 0.38, 0.0),
		false, Vector3(0, 0.6, 0), 88.0, Vector3.UP)

func impact(pos: Vector3, k := 1.0) -> void:
	_burst(pos, 8, 0.9, 1.3 * k, 5.0 * k, Color(0.6, 0.5, 0.4, 0.6), Color(0.6, 0.5, 0.4, 0.0), false, Vector3(0, -3, 0), 60.0)
	_burst(pos, 5, 0.25, 0.5 * k, 12.0, Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.3, 0.1, 0.0), true, Vector3(0, -9, 0), 70.0)

func sparks(pos: Vector3) -> void:
	_burst(pos, 10, 0.35, 0.5, 16.0, Color(1.0, 0.8, 0.5, 1.0), Color(1.0, 0.3, 0.1, 0.0), true, Vector3(0, -12, 0))

func muzzle(pos: Vector3, dir: Vector3) -> void:
	_burst(pos, 3, 0.08, 1.4, 4.0, Color(1.0, 0.8, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0), true, Vector3.ZERO, 15.0, dir)

func explosion(pos: Vector3, k: float) -> void:
	_burst(pos, int(26 * k) + 6, 0.7, 3.6 * k, 18.0 * k, Color(1.0, 0.85, 0.55, 1.0), Color(1.0, 0.25, 0.05, 0.0), true)
	_burst(pos, int(20 * k) + 4, 2.4, 5.0 * k, 9.0 * k, Color(0.25, 0.22, 0.2, 0.75), Color(0.3, 0.27, 0.24, 0.0), false, Vector3(0, 1.5, 0))
	_burst(pos, int(14 * k) + 3, 1.2, 0.4, 26.0 * k, Color(1.0, 0.7, 0.3, 1.0), Color(0.6, 0.2, 0.1, 0.0), true, Vector3(0, -20, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.omni_range = 30.0 * k + 6.0
	l.light_energy = 8.0 * k
	add_child(l)
	l.global_position = pos
	_lights.append({"node": l, "t": 0.0, "e": l.light_energy})
	Sfx.play_at("boom", pos, get_parent().listener(), -2.0 + 6.0 * k)

func tracer(from: Vector3, to: Vector3) -> void:
	for tr in _tracers:
		var n: MeshInstance3D = tr["node"]
		if not n.visible:
			tr["from"] = from
			tr["to"] = to
			tr["t"] = 0.0
			tr["len"] = from.distance_to(to)
			n.visible = true
			n.global_position = from
			if to.distance_to(from) > 0.1:
				n.look_at(to, Vector3.UP)
			return

func beam(from: Vector3, to: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	var ln := from.distance_to(to)
	b.size = Vector3(0.28, 0.28, ln)
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 1.0) * 3.0
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = (from + to) * 0.5
	if ln > 0.1:
		m.look_at(to, Vector3.UP)
	_beams.append({"node": m, "mat": mat, "t": 0.0, "col": col})
	_burst(to, 8, 0.4, 1.0, 8.0, Color(col.r, col.g, col.b, 1.0), Color(col.r, col.g, col.b, 0.0), true)

func _process(delta: float) -> void:
	for tr in _tracers:
		var n: MeshInstance3D = tr["node"]
		if not n.visible:
			continue
		tr["t"] += delta * 900.0
		if tr["t"] >= tr["len"]:
			n.visible = false
			continue
		var from: Vector3 = tr["from"]
		var to: Vector3 = tr["to"]
		n.global_position = from.lerp(to, minf(1.0, (tr["t"] + 3.5) / maxf(tr["len"], 0.01)))
	for i in range(_beams.size() - 1, -1, -1):
		var b: Dictionary = _beams[i]
		b["t"] += delta
		var k: float = 1.0 - b["t"] / 0.22
		if k <= 0.0:
			b["node"].queue_free()
			_beams.remove_at(i)
			continue
		var c: Color = b["col"]
		b["mat"].albedo_color = Color(c.r, c.g, c.b, k) * 3.0
		b["node"].scale = Vector3(k, k, 1.0)
	for i in range(_lights.size() - 1, -1, -1):
		var l: Dictionary = _lights[i]
		l["t"] += delta
		var k: float = 1.0 - l["t"] / 0.5
		if k <= 0.0:
			l["node"].queue_free()
			_lights.remove_at(i)
		else:
			l["node"].light_energy = l["e"] * k * k

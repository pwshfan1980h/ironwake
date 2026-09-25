class_name Projectiles
extends Node3D
## Sabots (slow, visible, dodgeable enemy rounds) and SRMs (player/lance dumbfire missiles).

var mission: Node
var sabots: Array[Dictionary] = []
var missiles: Array[Dictionary] = []
var _sabot_core: StandardMaterial3D
var _sabot_shell: StandardMaterial3D
var _missile_mat: StandardMaterial3D

func setup(m: Node) -> void:
	mission = m
	_sabot_core = StandardMaterial3D.new()
	_sabot_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sabot_core.albedo_color = Color(1.0, 0.9, 0.7) * 3.0
	_sabot_shell = StandardMaterial3D.new()
	_sabot_shell.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sabot_shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sabot_shell.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sabot_shell.albedo_color = Color(1.0, 0.25, 0.1, 0.8) * 2.0
	_missile_mat = StandardMaterial3D.new()
	_missile_mat.albedo_color = Color("3a3c40")
	_missile_mat.emission_enabled = true
	_missile_mat.emission = Color(1.0, 0.6, 0.3)
	_missile_mat.emission_energy_multiplier = 0.6

func spawn_sabot(from: Vector3, to: Vector3, speed: float, dmg: float, drill: bool) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = from
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.45
	cm.height = 0.9
	core.mesh = cm
	core.material_override = _sabot_core
	n.add_child(core)
	var shell := MeshInstance3D.new()
	var sm := CapsuleMesh.new()
	sm.radius = 0.8
	sm.height = 5.0
	shell.mesh = sm
	shell.material_override = _sabot_shell
	shell.rotation.x = PI / 2
	shell.position.z = 1.6
	n.add_child(shell)
	var l := OmniLight3D.new()
	l.light_color = Color("ff5a2a")
	l.light_energy = 3.0
	l.omni_range = 12.0
	n.add_child(l)
	var trail: CPUParticles3D = mission.fx.make_trail(Color(1.0, 0.4, 0.15), 0.7)
	n.add_child(trail)
	var vel := (to - from).normalized() * speed
	n.look_at(from + vel, Vector3.UP)
	sabots.append({"node": n, "vel": vel, "life": 6.0, "dmg": dmg, "drill": drill, "min_d": 999.0, "done": false})

func spawn_missile(from: Vector3, dir: Vector3, owner: Node) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = from
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = 1.1
	body.mesh = cm
	body.material_override = _missile_mat
	body.rotation.x = PI / 2
	n.add_child(body)
	n.add_child(mission.fx.make_trail(Color(0.75, 0.7, 0.62), 1.0, true))
	n.look_at(from + dir, Vector3.UP)
	missiles.append({"node": n, "vel": dir * 60.0, "life": 4.0, "owner": owner, "age": 0.0})

func _process(delta: float) -> void:
	_tick_sabots(delta)
	_tick_missiles(delta)

func _dist_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * tt)

func _tick_sabots(delta: float) -> void:
	var player: Mech = mission.player
	for i in range(sabots.size() - 1, -1, -1):
		var s: Dictionary = sabots[i]
		var n: Node3D = s["node"]
		n.position += s["vel"] * delta
		s["life"] -= delta
		var dead := false
		var d := _dist_seg(n.position, player.position + Vector3(0, 2.5, 0), player.position + Vector3(0, 9.5, 0))
		if d < s["min_d"]:
			s["min_d"] = d
		if player.alive and d < 2.6:
			player.take_hit(s["dmg"])
			mission.on_player_hit(s["drill"])
			mission.fx.explosion(n.position, 0.35)
			dead = true
		elif not s["done"] and s["min_d"] < 30.0 and d > s["min_d"] + 1.0:
			s["done"] = true
			mission.on_sabot_missed(s["min_d"], s["drill"])
		if n.position.y < mission.terrain.sample(n.position.x, n.position.z) or s["life"] <= 0.0:
			if not dead:
				mission.fx.impact(n.position, 2.0)
			dead = true
		if dead:
			n.queue_free()
			sabots.remove_at(i)

func _tick_missiles(delta: float) -> void:
	for i in range(missiles.size() - 1, -1, -1):
		var m: Dictionary = missiles[i]
		var n: Node3D = m["node"]
		m["age"] += delta
		m["vel"] = m["vel"].normalized() * minf(150.0, m["vel"].length() + 180.0 * delta)
		var step: Vector3 = m["vel"] * delta
		var hit: Dictionary = mission.raycast(n.position, step.normalized(), step.length() + 1.5)
		var boom: bool = hit["dist"] < step.length() + 1.5
		n.position += step
		m["life"] -= delta
		if boom or m["life"] <= 0.0:
			var at: Vector3 = hit["pos"] if boom else n.position
			mission.fx.explosion(at, 0.45)
			mission.splash(at, 6.0, 20.0, m["owner"])
			n.queue_free()
			missiles.remove_at(i)

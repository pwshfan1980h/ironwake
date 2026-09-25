class_name Drone
extends Node3D
## Sable combine hover drone. Telegraphs each shot with a glowing charge, then fires a slow sabot.

const RADIUS := 2.3
const CHARGE_TIME := 0.95

var mission: Node
var hp := 70.0
var alive := true
var anchor := Vector3.ZERO
var altitude := 15.0
var engaged := false
var aggro_range := 160.0
var invulnerable := false
var drill := false
var fire_interval := 4.0
var sabot_speed := 52.0
var sabot_dmg := 10.0
var lead := 0.35
var jitter := 10.0
var cooldown := 2.5
var charge := 0.0
var assigned: Array[String] = []
var t := randf() * 20.0
var fall_v := 0.0
var eye_mat: StandardMaterial3D
var body_mat: StandardMaterial3D
var glow: OmniLight3D
var rotors: Array[Node3D] = []
var hit_flash := 0.0

func setup(m: Node, at: Vector3, alt := 15.0) -> void:
	mission = m
	altitude = alt
	anchor = at
	position = Vector3(at.x, mission.terrain.sample(at.x, at.z) + altitude, at.z)
	_build()

func _build() -> void:
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("2a2624")
	body_mat.metallic = 0.6
	body_mat.roughness = 0.45
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("b8a88a")
	trim.roughness = 0.6
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color.BLACK
	eye_mat.emission_enabled = true
	eye_mat.emission = Color("ff3a2a")
	eye_mat.emission_energy_multiplier = 2.0
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 1.6
	sm.radial_segments = 12
	sm.rings = 6
	body.mesh = sm
	body.material_override = body_mat
	add_child(body)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.45
	bm.bottom_radius = 1.45
	bm.height = 0.35
	bm.radial_segments = 12
	band.mesh = bm
	band.material_override = trim
	add_child(band)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.42
	em.height = 0.84
	eye.mesh = em
	eye.material_override = eye_mat
	eye.position = Vector3(0, -0.1, -1.15)
	add_child(eye)
	var barrel := MeshInstance3D.new()
	var brm := CylinderMesh.new()
	brm.top_radius = 0.16
	brm.bottom_radius = 0.2
	brm.height = 1.6
	barrel.mesh = brm
	barrel.material_override = body_mat
	barrel.rotation.x = PI / 2
	barrel.position = Vector3(0, -0.75, -1.1)
	add_child(barrel)
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.45)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.22, 0.18, 1.9)
		arm.mesh = am
		arm.material_override = body_mat
		arm.position = Vector3(cos(a), 0.2, sin(a)) * 1.3
		arm.rotation.y = -a + PI / 2
		add_child(arm)
		var rotor := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 1.0
		rm.bottom_radius = 1.0
		rm.height = 0.05
		rm.radial_segments = 16
		rotor.mesh = rm
		rotor.material_override = disc_mat
		rotor.position = Vector3(cos(a), 0.35, sin(a)) * 2.25 + Vector3(0, 0.35, 0)
		add_child(rotor)
		rotors.append(rotor)
	glow = OmniLight3D.new()
	glow.light_color = Color("ff4a2a")
	glow.omni_range = 14.0
	glow.light_energy = 0.0
	glow.position = Vector3(0, -0.2, -1.6)
	add_child(glow)

func tick(delta: float) -> void:
	t += delta
	if not alive:
		fall_v += 22.0 * delta
		position.y -= fall_v * delta
		rotation.z += delta * 3.0
		if position.y < mission.terrain.sample(position.x, position.z):
			mission.fx.explosion(position, 0.7)
			queue_free()
		return
	var player: Mech = mission.player
	var to_p := player.position - position
	var flat := Vector2(to_p.x, to_p.z).length()
	if not engaged and flat < aggro_range and player.alive and not player.frozen:
		engaged = true
	var j := jitter if engaged else 3.0
	var goal := anchor + Vector3(sin(t * 0.45 + anchor.x) * j, 0.0, cos(t * 0.37 + anchor.z) * j)
	goal.y = mission.terrain.sample(goal.x, goal.z) + altitude + sin(t * 1.3) * 1.2
	position = position.lerp(goal, 1.0 - exp(-1.2 * delta))
	var look := player.position + Vector3(0, 6, 0)
	if look.distance_to(position) > 1.0:
		look_at(look, Vector3.UP)
	for r in rotors:
		r.rotation.y += delta * 40.0
	hit_flash = maxf(0.0, hit_flash - delta * 5.0)
	body_mat.emission_enabled = hit_flash > 0.0
	body_mat.emission = Color(1, 0.6, 0.3) * hit_flash
	# telegraphed fire cycle
	if engaged and player.alive and not player.frozen:
		if charge > 0.0:
			charge += delta
			var k := charge / CHARGE_TIME
			eye_mat.emission_energy_multiplier = 2.0 + 14.0 * k * k
			glow.light_energy = 6.0 * k
			if charge >= CHARGE_TIME:
				_fire(player)
		else:
			cooldown -= delta
			if cooldown <= 0.0 and mission.has_los(position, player.position + Vector3(0, 6, 0)):
				charge = 0.001
				Sfx.play_at("charge", position, mission.listener(), 2.0)
	else:
		charge = 0.0

func charging() -> bool:
	return alive and charge > 0.0

func _fire(player: Mech) -> void:
	charge = 0.0
	cooldown = fire_interval + randf() * 1.2
	eye_mat.emission_energy_multiplier = 2.0
	glow.light_energy = 0.0
	var muzzle := global_transform * Vector3(0, -0.75, -2.0)
	var aim := player.position + Vector3(0, 6.0, 0)
	var tof := muzzle.distance_to(aim) / sabot_speed
	aim += player.vel * tof * lead
	mission.spawn_sabot(muzzle, aim, sabot_speed, sabot_dmg, drill)

func damage(amount: float, source: Node) -> void:
	if not alive:
		return
	hit_flash = 1.0
	if invulnerable:
		mission.fx.sparks(position)
		return
	engaged = true
	hp -= amount
	if hp <= 0.0:
		alive = false
		charge = 0.0
		glow.light_energy = 0.0
		eye_mat.emission_energy_multiplier = 0.0
		mission.fx.explosion(position, 1.0)
		mission.on_drone_killed(self, source)

class_name Cockpit
extends Node3D
## First-person cockpit: a thin canopy frame around big glass panes, a low dash carrying three MFDs,
## a throttle lever and stick that track the controls, and warning lamps.
## Rides the player's torso (Mission sets its transform); the camera sits on a sprung pilot head.
## Local space: pilot eye at the origin, looking down -Z, +X to the right.

const GLASS := preload("res://shaders/glass.gdshader")
const MFD_SIZE := Vector2i(480, 320)

var mission: Node
var head: Node3D
var mfds: Array[Mfd] = []
var throttle_pivot: Node3D
var stick_pivot: Node3D
var lamps := {}   # name -> StandardMaterial3D
var glass_mat: ShaderMaterial
var bob := 0.0
var bob_v := 0.0
var sway := Vector2.ZERO
var sway_v := Vector2.ZERO
var stick_in := Vector2.ZERO
var boot := 0.0

var m_frame: StandardMaterial3D
var m_panel: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_trim: StandardMaterial3D
var m_grip: StandardMaterial3D

func setup(m: Node, cam: Camera3D) -> void:
	mission = m
	m_frame = _mat(Color("1b1d20"), 0.7, 0.42)
	m_panel = _mat(Color("2a2d31"), 0.25, 0.78)
	m_dark = _mat(Color("0d0e0f"), 0.3, 0.7)
	m_trim = _mat(Color("8c2029"), 0.1, 0.55)
	m_grip = _mat(Color("34322f"), 0.2, 0.6)
	head = Node3D.new()
	add_child(head)
	if cam.get_parent():
		cam.get_parent().remove_child(cam)
	head.add_child(cam)
	cam.transform = Transform3D.IDENTITY
	_build_canopy()
	_build_dash()
	_build_controls()
	var l := OmniLight3D.new()
	l.light_color = Color("ffc890")
	l.light_energy = 0.6
	l.omni_range = 1.9
	l.position = Vector3(0, 0.1, -0.35)
	add_child(l)

static func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, basis := Basis(), parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	(parent if parent else self).add_child(mi)
	return mi

## A square-section bar from a to b.
func _strut(a: Vector3, b: Vector3, th: float, mat: Material = null) -> void:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	_box(Vector3(th, th, d.length() + th * 0.6), (a + b) * 0.5, mat if mat else m_frame, Basis.looking_at(d, up))

## Point at azimuth / elevation (degrees; +azimuth to the right) and distance from the eye.
static func _at(az: float, el: float, d: float) -> Vector3:
	var a := deg_to_rad(az)
	var e := deg_to_rad(el)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)) * d

## Basis whose +Z points from pos back at the pilot's eye (for screens and panels).
static func _face_eye(pos: Vector3) -> Basis:
	return Basis.looking_at(pos, Vector3.UP)

# ---------------------------------------------------------------- canopy
func _build_canopy() -> void:
	# right-hand points; the left side mirrors x
	var F0 := Vector3(0.0, -0.3, -1.06)
	var F1 := Vector3(0.8, -0.34, -0.96)
	var F2 := Vector3(1.18, -0.46, -0.5)
	var F3 := Vector3(1.22, -0.46, 0.62)
	var T0 := Vector3(0.0, 0.66, -0.66)
	var T1 := Vector3(0.7, 0.58, -0.58)
	var T2 := Vector3(1.04, 0.44, -0.28)
	var T3 := Vector3(1.04, 0.44, 0.62)
	var R0 := Vector3(0.0, 0.84, -0.05)
	var R1 := Vector3(0.0, 0.84, 0.62)
	var mx := func(v: Vector3) -> Vector3: return Vector3(-v.x, v.y, v.z)
	# glass
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# windshield: one pane across both halves, so grime only gathers at the outer frame
	_pane(st, [mx.call(F1), F0, T0, mx.call(T1)], [Vector2(0, 1), Vector2(0.5, 1), Vector2(0.5, 0), Vector2(0, 0)])
	_pane(st, [F0, F1, T1, T0], [Vector2(0.5, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0.5, 0)])
	for s in [1.0, -1.0]:
		var f := func(v: Vector3) -> Vector3: return Vector3(v.x * s, v.y, v.z)
		_pane(st, [f.call(F1), f.call(F2), f.call(T2), f.call(T1)])
		_pane(st, [f.call(F2), f.call(F3), f.call(T3), f.call(T2)])
		_pane(st, [R0, f.call(T0), f.call(T1), f.call(T2)])
		_pane(st, [R0, f.call(T2), f.call(T3), R1])
	st.generate_normals()
	var glass := MeshInstance3D.new()
	glass.mesh = st.commit()
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS
	glass.material_override = glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	# frame: thin pillars and rails, heavier sills where the canopy meets the tub
	_strut(mx.call(F1), F0, 0.07)
	_strut(F0, F1, 0.07)
	_strut(mx.call(T1), T0, 0.045)
	_strut(T0, T1, 0.045)
	_strut(T0, R0, 0.05)
	_strut(R0, R1, 0.05)
	for s in [1.0, -1.0]:
		var f := func(v: Vector3) -> Vector3: return Vector3(v.x * s, v.y, v.z)
		_strut(f.call(F1), f.call(F2), 0.08)
		_strut(f.call(F2), f.call(F3), 0.08)
		_strut(f.call(F1), f.call(T1), 0.03)
		_strut(f.call(F2), f.call(T2), 0.03)
		_strut(f.call(F3), f.call(T3), 0.07)
		_strut(f.call(T1), f.call(T2), 0.05)
		_strut(f.call(T2), f.call(T3), 0.05)
		_strut(f.call(T3), R1, 0.07)
		_strut(R0, f.call(T2), 0.03)
		# red trim strip along the sill
		_strut(f.call(F1) + Vector3(0, 0.045, 0), f.call(F2) + Vector3(0, 0.045, 0), 0.012, m_trim)
	# tub: skin hung under every sill down to the floor, so nothing below the glass is open
	var tub := SurfaceTool.new()
	tub.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sill := [mx.call(F3), mx.call(F2), mx.call(F1), F0, F1, F2, F3]
	for i in sill.size() - 1:
		var a: Vector3 = sill[i]
		var b: Vector3 = sill[i + 1]
		_pane(tub, [Vector3(a.x, -1.3, a.z), Vector3(b.x, -1.3, b.z), b, a])
	tub.generate_normals()
	var skin := MeshInstance3D.new()
	skin.mesh = tub.commit()
	var skin_mat: StandardMaterial3D = m_panel.duplicate()
	skin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.material_override = skin_mat
	add_child(skin)
	# rear bulkhead behind the seat
	_box(Vector3(2.5, 2.2, 0.08), Vector3(0, -0.25, 0.68), m_panel)

## Quad a-b-c-d (bottom-left, bottom-right, top-right, top-left); UV v=1 along the bottom edge.
func _pane(st: SurfaceTool, v: Array, uv: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])

# ---------------------------------------------------------------- dash, consoles, screens
func _build_dash() -> void:
	# tub: floor, side walls, front bulkhead under the windshield
	_box(Vector3(2.5, 0.08, 1.9), Vector3(0, -1.28, -0.2), m_dark)
	for s in [1.0, -1.0]:
		_box(Vector3(0.08, 0.8, 1.2), Vector3(1.21 * s, -0.88, 0.06), m_panel)
	_box(Vector3(1.9, 0.95, 0.12), Vector3(0, -0.8, -1.06), m_panel)
	# dash top behind the screens, and the dash body below them
	_box(Vector3(1.75, 0.04, 0.24), Vector3(0, -0.33, -0.95), m_panel)
	_box(Vector3(1.4, 0.6, 0.28), Vector3(0, -0.79, -0.88), m_panel)
	# screen bank: a slab facing the pilot, with a centre MFD and two canted side MFDs
	var pages := [["tac", _at(0.0, -24.0, 0.86), Vector2(0.3, 0.2)],
		["sys", _at(-28.0, -23.0, 0.84), Vector2(0.27, 0.18)],
		["drv", _at(28.0, -23.0, 0.84), Vector2(0.27, 0.18)]]
	for pg in pages:
		var pos: Vector3 = pg[1]
		var sz: Vector2 = pg[2]
		var b := _face_eye(pos)
		# housing and bezel sit behind the screen
		_box(Vector3(sz.x + 0.06, sz.y + 0.06, 0.1), pos - b.z * 0.06, m_panel, b)
		_box(Vector3(sz.x + 0.024, sz.y + 0.024, 0.02), pos - b.z * 0.012, m_dark, b)
		_screen(pg[0], pos, b, sz)
	# side consoles
	for s in [1.0, -1.0]:
		_box(Vector3(0.36, 0.56, 0.9), Vector3(0.84 * s, -0.94, -0.3), m_panel)
		_box(Vector3(0.34, 0.03, 0.88), Vector3(0.84 * s, -0.65, -0.3), m_dark)
		for i in 3:
			for j in 2:
				var lit := (i + j + int(s > 0.0)) % 3 == 0
				var mat := m_dark
				if lit:
					mat = _lamp_mat(Color("ff2a3a"), 1.2)
				_box(Vector3(0.05, 0.02, 0.05), Vector3(0.84 * s + (j - 0.5) * 0.1, -0.625, 0.0 - i * 0.1), mat)
	# warning lamp row across the top of the centre screen
	var names := ["HEAT", "ARMR", "INCM", "SHDN", "LINK"]
	var plate_pos := Vector3(0, -0.19, -0.892)
	var plate_b := _face_eye(plate_pos)
	_box(Vector3(0.34, 0.06, 0.03), plate_pos, m_dark, plate_b)
	for i in names.size():
		var x := (i - 2) * 0.062
		var pos := Vector3(x, -0.2, -0.88)
		var b := _face_eye(pos)
		var mat := _lamp_mat(Color("5fd8ff") if names[i] == "LINK" else Color("ff3b30"), 0.0)
		lamps[names[i]] = mat
		b = plate_b
		pos += b.z * 0.012
		_box(Vector3(0.048, 0.014, 0.006), pos, mat, b)
		var lb := Label3D.new()
		lb.text = names[i]
		lb.font = Game.font_mono
		lb.font_size = 28
		lb.pixel_size = 0.0005
		lb.modulate = Color(0.9, 0.86, 0.78, 0.8)
		lb.outline_size = 0
		lb.transform = Transform3D(b, pos + b.z * 0.004 + b.y * 0.02)
		add_child(lb)

func _lamp_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _screen(page: String, pos: Vector3, b: Basis, sz: Vector2) -> void:
	var vp := SubViewport.new()
	vp.size = MFD_SIZE
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var mfd := Mfd.new()
	mfd.size = Vector2(MFD_SIZE)
	mfd.setup(mission, page)
	vp.add_child(mfd)
	mfds.append(mfd)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.roughness = 0.5   # matte anti-glare coating
	mat.metallic_specular = 0.2
	mat.emission_enabled = true
	mat.emission_texture = vp.get_texture()
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, pos)
	add_child(mi)

# ---------------------------------------------------------------- throttle + stick
func _build_controls() -> void:
	throttle_pivot = Node3D.new()
	throttle_pivot.position = Vector3(-0.6, -0.55, -0.56)
	add_child(throttle_pivot)
	_box(Vector3(0.36, 0.04, 0.5), Vector3(-0.6, -0.58, -0.5), m_panel)   # console top
	_box(Vector3(0.08, 0.03, 0.26), Vector3(-0.6, -0.56, -0.56), m_dark)   # gate
	_box(Vector3(0.022, 0.2, 0.022), Vector3(0, 0.1, 0), m_frame, Basis(), throttle_pivot)
	_box(Vector3(0.1, 0.05, 0.06), Vector3(-0.02, 0.21, 0), m_grip, Basis(), throttle_pivot)
	_box(Vector3(0.02, 0.012, 0.03), Vector3(0.03, 0.238, 0), _lamp_mat(Color("c01020"), 0.7), Basis(), throttle_pivot)
	stick_pivot = Node3D.new()
	stick_pivot.position = Vector3(0.6, -0.56, -0.54)
	add_child(stick_pivot)
	_box(Vector3(0.36, 0.04, 0.5), Vector3(0.6, -0.58, -0.5), m_panel)   # console top
	_box(Vector3(0.11, 0.03, 0.11), Vector3(0.6, -0.56, -0.54), m_dark)   # boot
	_box(Vector3(0.026, 0.2, 0.026), Vector3(0, 0.1, 0), m_frame, Basis(), stick_pivot)
	_box(Vector3(0.05, 0.11, 0.06), Vector3(0, 0.24, 0.005), m_grip, Basis(Vector3.RIGHT, -0.25), stick_pivot)
	_box(Vector3(0.018, 0.018, 0.018), Vector3(0, 0.3, -0.02), _lamp_mat(Color("c01020"), 0.7), Basis(), stick_pivot)

# ---------------------------------------------------------------- per frame
func footfall(a: float) -> void:
	bob_v -= 0.55 * a
	sway_v.x += randf_range(-0.05, 0.05) * a

func impact(k: float) -> void:
	bob_v -= 1.4 * k
	sway_v += Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)) * 0.4 * k

## Stick deflection: x = turn/twist input, y = pitch input (both roughly -1..1).
func stick_input(v: Vector2) -> void:
	stick_in = stick_in.lerp(v.clampf(-1.0, 1.0), 0.5)

func update(delta: float) -> void:
	var p: Mech = mission.player
	# pilot head on a spring: dips on footfalls, sways on hits
	bob_v += (-110.0 * bob - 11.0 * bob_v) * delta
	bob += bob_v * delta
	sway_v += (-60.0 * sway - 8.0 * sway_v) * delta
	sway += sway_v * delta
	head.position = Vector3(sway.x * 0.05, bob * 0.08, 0.0)
	head.rotation = Vector3(bob * 0.03 + sway.y * 0.02, 0.0, sway.x * 0.04)
	throttle_pivot.rotation.x = lerp_angle(throttle_pivot.rotation.x, -p.throttle * 0.55, 1.0 - exp(-14.0 * delta))
	stick_in = stick_in.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
	stick_pivot.rotation = Vector3(stick_in.y * 0.3, 0.0, -stick_in.x * 0.35)
	# lamps
	var blink := int(mission.clock * 4.0) % 2 == 0
	_lamp("HEAT", p.heat > 75.0, blink)
	_lamp("ARMR", p.armor < 35.0, blink)
	_lamp("INCM", _incoming(p), blink)
	_lamp("SHDN", p.overheat > 0.0, true)
	_lamp("LINK", boot >= 1.0, true)
	for m in mfds:
		m.boot = boot
	glass_mat.set_shader_parameter("damage", clampf((60.0 - p.armor) / 60.0, 0.0, 1.0))

func _lamp(n: String, on: bool, blink: bool) -> void:
	var m: StandardMaterial3D = lamps[n]
	m.emission_energy_multiplier = (3.0 if blink else 1.2) if on else 0.05

func _incoming(p: Mech) -> bool:
	for s in mission.projectiles.sabots:
		var to_p: Vector3 = p.position + Vector3(0, 6, 0) - s["node"].position
		if not s["done"] and to_p.length() < 180.0 and to_p.dot(s["vel"]) > 0.0:
			return true
	return false

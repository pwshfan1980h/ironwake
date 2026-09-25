class_name Mfd
extends Control
## One cockpit multi-function display, drawn into a SubViewport that textures a screen in the cockpit.
## Pages: "sys" (armor, heat, weapons), "tac" (radar), "drv" (throttle, speed, torso twist, comms).

const AMBER := Color("ffb347")
const AMBER_DIM := Color(1.0, 0.7, 0.28, 0.35)
const BONE := Color("e9e4d6")
const THREAT := Color("ff3b30")
const CYAN := Color("5fd8ff")
const BG := Color(0.025, 0.028, 0.03)
const RADAR_RANGE := 320.0

var mission: Node
var page := "tac"
var boot := 0.0   # 0 = dark, 1 = fully on

func setup(m: Node, p: String) -> void:
	mission = m
	page = p

func _process(_delta: float) -> void:
	queue_redraw()

func _text(pos: Vector2, s: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	var f := font if font else Game.font_mono
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width <= 0.0:   # right-align on pos.x
		pos.x -= f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		align = HORIZONTAL_ALIGNMENT_LEFT
	draw_string(f, pos, s, align, width, fs, col)

func _bar(r: Rect2, k: float, col: Color) -> void:
	draw_rect(r, Color(col.r, col.g, col.b, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), col)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var p: Mech = mission.player if mission else null
	if p == null or boot <= 0.0:
		return
	if boot < 1.0:
		_draw_boot()
	else:
		match page:
			"sys":
				_draw_sys(p)
			"tac":
				_draw_tac(p)
			"drv":
				_draw_drv(p)
	# frame + scanlines
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), AMBER_DIM, false, 2.0)
	for y in range(0, int(size.y), 3):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.22), 1.0)

func _draw_boot() -> void:
	var k := boot
	_text(Vector2(24, 48), "KNIFE CELL · UNIT 27", 18, AMBER)
	var lines := ["BUS POWER", "ACTUATOR CAL", "SENSOR MAST", "FIRE CONTROL", "PILOT LINK"]
	for i in lines.size():
		var on := k * lines.size() > i + 0.5
		_text(Vector2(24, 96 + i * 30), lines[i], 16, AMBER if on else AMBER_DIM)
		_text(Vector2(size.x - 24, 96 + i * 30), "OK" if on else "··", 16, AMBER if on else AMBER_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_bar(Rect2(24, size.y - 44, size.x - 48, 10), k, AMBER)

# ---------------------------------------------------------------- SYS: armor, heat, weapons
func _draw_sys(p: Mech) -> void:
	_text(Vector2(18, 32), "SYS", 18, AMBER)
	_text(Vector2(size.x - 18, 32), "ARMOR %d%%" % int(p.armor), 18, AMBER if p.armor > 35.0 else THREAT, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	# paper doll: torso, arms, legs, shaded by armor
	var c := Vector2(110, 176)
	var col := AMBER.lerp(THREAT, clampf(1.0 - p.armor / 100.0, 0.0, 1.0))
	if p.flash > 0.3 and int(Time.get_ticks_msec() / 80) % 2 == 0:
		col = BONE
	var parts := [Rect2(-30, -64, 60, 58), Rect2(-62, -56, 26, 64), Rect2(36, -56, 26, 64),
		Rect2(-28, 0, 22, 78), Rect2(6, 0, 22, 78), Rect2(-12, -84, 24, 16)]
	for r in parts:
		var rr := Rect2(c + r.position, r.size)
		draw_rect(rr, Color(col.r, col.g, col.b, 0.28))
		draw_rect(rr, col, false, 2.0)
	# heat column
	var hx := 214.0
	var hr := Rect2(hx, 54, 26, 230)
	_text(Vector2(hx - 8, 300), "HEAT", 14, AMBER_DIM)
	draw_rect(hr, Color(1, 0.6, 0.2, 0.12))
	var hk := clampf(p.heat / 100.0, 0.0, 1.0)
	var hcol := THREAT if p.heat > 75.0 or p.overheat > 0.0 else AMBER
	draw_rect(Rect2(hr.position.x, hr.end.y - hr.size.y * hk, hr.size.x, hr.size.y * hk), hcol)
	draw_line(Vector2(hx - 6, hr.end.y - hr.size.y * 0.75), Vector2(hx + 32, hr.end.y - hr.size.y * 0.75), THREAT, 2.0)
	if p.overheat > 0.0 and int(Time.get_ticks_msec() / 200) % 2 == 0:
		_text(Vector2(18, size.y - 18), "SHUTDOWN · VENTING", 16, THREAT)
	# weapons
	var wx := 262.0
	_text(Vector2(wx, 70), "CHAIN", 14, AMBER_DIM)
	for i in p.weapons.size():
		var w: Dictionary = p.weapons[i]
		var y := 108.0 + i * 62.0
		var ready: bool = w["cd"] <= 0.0 and p.overheat <= 0.0
		var nxt: bool = i == p.chain_index
		if nxt:
			draw_rect(Rect2(wx - 8, y - 24, size.x - wx - 10, 50), Color(1, 0.7, 0.28, 0.12))
		_text(Vector2(wx, y), ("▶ " if nxt else "  ") + String(w["name"]), 18, AMBER if ready else AMBER_DIM)
		_bar(Rect2(wx + 24, y + 10, size.x - wx - 50, 8), 1.0 - w["cd"] / w["cool"], AMBER if ready else AMBER_DIM)

# ---------------------------------------------------------------- TAC: radar
func _to_radar(p: Mech, world: Vector3, c: Vector2, r: float) -> Vector2:
	var rel := world - p.position
	var a := p.aim_yaw
	var x := rel.x * cos(a) - rel.z * sin(a)
	var y := -rel.x * sin(a) - rel.z * cos(a)
	return c + Vector2(x, -y) * (r / RADAR_RANGE)

func _draw_tac(p: Mech) -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.56)
	var r := size.y * 0.42
	_text(Vector2(18, 32), "TAC", 18, AMBER)
	_text(Vector2(size.x - 18, 32), "%dM" % int(RADAR_RANGE), 16, AMBER_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	for k in [1.0, 0.66, 0.33]:
		draw_arc(c, r * k, 0, TAU, 48, AMBER_DIM, 1.5)
	# camera view cone
	var cam: Camera3D = mission.cam
	var half := atan(tan(deg_to_rad(cam.fov) * 0.5) * size.x / size.y) if cam else 0.9
	half = minf(half, 1.1)
	for s in [-1.0, 1.0]:
		draw_line(c, c + Vector2(sin(half * s), -cos(half * s)) * r, Color(1, 0.7, 0.28, 0.5), 1.5)
	# legs vs torso
	var leg := Vector2(sin(p.twist), -cos(p.twist))
	draw_line(c, c + leg * 26.0, CYAN, 3.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(-7, 7), c + Vector2(7, 7)]), AMBER)
	# waypoint
	var wp = mission.waypoint
	if wp != null:
		var q := _to_radar(p, wp, c, r)
		if q.distance_to(c) > r:
			q = c + (q - c).normalized() * r
		draw_polyline(PackedVector2Array([q + Vector2(0, -8), q + Vector2(8, 0), q + Vector2(0, 8), q + Vector2(-8, 0), q + Vector2(0, -8)]), CYAN, 2.0)
	# lance
	for m in mission.lance:
		if not m.alive:
			continue
		var q := _to_radar(p, m.position, c, r)
		if q.distance_to(c) <= r:
			draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), Game.color_of(m.callsign))
	# drones
	for d in mission.drones:
		if not is_instance_valid(d) or not d.alive:
			continue
		var q := _to_radar(p, d.position, c, r)
		if q.distance_to(c) > r:
			continue
		var col := THREAT
		if d.charging() and int(Time.get_ticks_msec() / 90) % 2 == 0:
			col = BONE
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -8), q + Vector2(7, 6), q + Vector2(-7, 6)]), col)
	# sabots in flight
	for s in mission.projectiles.sabots:
		var q := _to_radar(p, s["node"].position, c, r)
		if q.distance_to(c) <= r:
			draw_circle(q, 3.0, THREAT)
	if wp != null:
		var dist := Vector2(wp.x - p.position.x, wp.z - p.position.z).length()
		_text(Vector2(18, size.y - 18), "%s  %dM" % [mission.waypoint_name, int(dist)], 16, CYAN)

# ---------------------------------------------------------------- DRV: throttle, speed, twist, comms
func _draw_drv(p: Mech) -> void:
	_text(Vector2(18, 32), "DRV", 18, AMBER)
	# throttle ladder: reverse zone below zero
	var tr := Rect2(34, 52, 34, 240)
	var zero_y := tr.position.y + tr.size.y * 0.72
	draw_rect(tr, Color(1, 0.7, 0.28, 0.1))
	draw_rect(Rect2(tr.position.x, zero_y, tr.size.x, tr.end.y - zero_y), Color(1, 0.23, 0.19, 0.12))
	for i in 11:
		var y := lerpf(zero_y, tr.position.y, i / 10.0)
		draw_line(Vector2(tr.end.x, y), Vector2(tr.end.x + (12 if i % 5 == 0 else 6), y), AMBER_DIM, 1.5)
	var sk := p.speed / Mech.RUN if p.speed >= 0.0 else p.speed / Mech.BACK
	var sy := zero_y - (tr.size.y * 0.72) * sk if sk >= 0.0 else zero_y - (tr.end.y - zero_y) * sk
	draw_rect(Rect2(tr.position.x + 6, minf(sy, zero_y), tr.size.x - 12, absf(zero_y - sy)), AMBER if sk >= 0.0 else THREAT)
	var tk := p.throttle
	var ty := zero_y - (tr.size.y * 0.72) * tk if tk >= 0.0 else zero_y - (tr.end.y - zero_y) * tk
	draw_colored_polygon(PackedVector2Array([Vector2(tr.position.x - 4, ty), Vector2(tr.position.x - 18, ty - 9), Vector2(tr.position.x - 18, ty + 9)]), BONE)
	draw_line(Vector2(tr.position.x - 4, ty), Vector2(tr.end.x + 4, ty), BONE, 2.0)
	_text(Vector2(tr.end.x + 18, zero_y + 6), "0", 14, AMBER_DIM)
	_text(Vector2(tr.end.x + 18, tr.position.y + 6), "100", 14, AMBER_DIM)
	_text(Vector2(tr.end.x + 18, tr.end.y), "REV", 14, THREAT)
	# speed readout
	_text(Vector2(size.x - 18, 96), "%d" % int(absf(p.speed) * 3.6), 64, AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 0, Game.font_display)
	_text(Vector2(size.x - 18, 120), "KM/H" + (" REV" if p.speed < -0.2 else ""), 16, AMBER_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(size.x - 18, 146), "THR %+d%%" % int(round(p.throttle * 100.0)), 16, BONE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	# torso twist dial
	var dc := Vector2(size.x - 108, 226)
	draw_arc(dc, 54, -PI * 0.5 - Mech.TWIST_MAX, -PI * 0.5 + Mech.TWIST_MAX, 32, AMBER_DIM, 3.0)
	var ta := -PI * 0.5 - p.twist
	draw_line(dc, dc + Vector2(cos(ta), sin(ta)) * 50.0, AMBER, 3.0)
	draw_line(dc, dc + Vector2(0, -34), CYAN, 3.0)
	_text(dc + Vector2(-60, 76), "TWIST %+d°" % int(rad_to_deg(p.twist)), 14, AMBER_DIM, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# comms activity
	var hud: Hud = mission.hud
	if hud and not hud.current.is_empty():
		var who: String = hud.current["who"]
		var col := Game.color_of(who)
		_text(Vector2(112, size.y - 18), "RX " + who, 16, col)
		for i in 8:
			var bh := 3.0 + absf(sin(hud.line_t * 13.0 + i * 1.7)) * 14.0
			draw_rect(Rect2(Vector2(112 + i * 7, size.y - 40 - bh), Vector2(4, bh)), col)

class_name Hud
extends Control
## Gameplay HUD + comms radio (voice lines with subtitles).

const BONE := Color("e9e4d6")
const DIM := Color(0.91, 0.89, 0.84, 0.5)
const THREAT := Color("ff3b30")
const PANEL := Color(0.05, 0.05, 0.05, 0.55)

var mission: Node
var objective := ""
var objective_hint := ""
var show_combat := false
var hit_t := 0.0
var damage_t := 0.0
var callout := ""
var callout_t := 0.0
var queue: Array[String] = []
var current := {}
var line_t := 0.0
var radio_player := AudioStreamPlayer.new()
var sys_player := AudioStreamPlayer.new()

func setup(m: Node) -> void:
	mission = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(radio_player)
	add_child(sys_player)
	radio_player.volume_db = 2.0
	radio_player.finished.connect(_next_line)

# ---------------------------------------------------------------- radio
func radio(id: String, front := false) -> void:
	if not Game.voice.has(id):
		return
	if Game.voice[id]["who"] == "SYSTEM":
		sys_player.stream = load("res://assets/voice/%s.mp3" % id)
		sys_player.play()
		return
	if front:
		queue.push_front(id)
	else:
		queue.append(id)
	if current.is_empty():
		_next_line()

func radio_idle() -> bool:
	return current.is_empty() and queue.is_empty()

func _next_line() -> void:
	current = {}
	if queue.is_empty():
		return
	var id: String = queue.pop_front()
	current = Game.voice[id].duplicate()
	line_t = 0.0
	radio_player.stream = load("res://assets/voice/%s.mp3" % id)
	radio_player.play()

func hit_marker() -> void:
	hit_t = 0.14

func flash_damage() -> void:
	damage_t = 0.5

func show_callout(text: String) -> void:
	callout = text
	callout_t = 1.4

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	damage_t = maxf(0.0, damage_t - delta)
	callout_t = maxf(0.0, callout_t - delta)
	if not current.is_empty():
		line_t += delta
		if line_t > float(current["dur"]) + 1.0 and not radio_player.playing:
			_next_line()
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	draw_string(font if font else Game.font_mono, pos, s, align, width, size, col)

func _bar(r: Rect2, k: float, col: Color) -> void:
	draw_rect(r, Color(col.r, col.g, col.b, 0.18))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), col)

func _screen(world: Vector3) -> Variant:
	var cam: Camera3D = mission.cam
	if cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)

func _draw() -> void:
	var sz := size
	if sz.x < 320.0 or sz.y < 240.0:
		return
	var c := sz * 0.5
	var p: Mech = mission.player
	var sc := clampf(sz.y / 900.0, 0.75, 1.6)
	var fs := int(13 * sc)
	# damage vignette
	if damage_t > 0.0:
		var a := damage_t * 0.9
		var e := 90.0 * sc
		draw_rect(Rect2(0, 0, sz.x, e), Color(0.8, 0.05, 0.02, a * 0.5))
		draw_rect(Rect2(0, sz.y - e, sz.x, e), Color(0.8, 0.05, 0.02, a * 0.5))
		draw_rect(Rect2(0, 0, e, sz.y), Color(0.8, 0.05, 0.02, a * 0.4))
		draw_rect(Rect2(sz.x - e, 0, e, sz.y), Color(0.8, 0.05, 0.02, a * 0.4))
	_draw_objective(sc)
	_draw_radio(sz, sc)
	if not show_combat:
		return
	_draw_world_markers(sz, sc)
	_draw_compass(sz, sc)
	# reticle
	var r := 13.0 * sc
	var rc := BONE if p.overheat <= 0.0 else THREAT
	draw_arc(c, r, 0, TAU, 32, rc, 1.6)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * (r + 4 * sc), c + d * (r + 13 * sc), rc, 1.6)
	draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), rc)
	if hit_t > 0.0:
		var k := 9.0 * sc
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * k, c + d * k * 2.0, Color(1, 0.85, 0.5), 2.2)
	_draw_threats(sz, sc)
	# armor + dodge (bottom left)
	var bl := Vector2(28 * sc, sz.y - 96 * sc)
	draw_rect(Rect2(bl - Vector2(12, 22) * sc, Vector2(270, 108) * sc), PANEL)
	_text(bl, "ARMOR", fs, DIM)
	_text(bl + Vector2(240 * sc, 0), "%d%%" % int(p.armor), fs, BONE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_bar(Rect2(bl + Vector2(0, 8 * sc), Vector2(240 * sc, 8 * sc)), p.armor / 100.0, BONE if p.armor > 35.0 else THREAT)
	_text(bl + Vector2(0, 42 * sc), "DODGE  SHIFT + A / D", fs, DIM)
	for i in 2:
		var k := clampf(p.dodge_charges - i, 0.0, 1.0)
		_bar(Rect2(bl + Vector2(i * 124 * sc, 50 * sc), Vector2(116 * sc, 8 * sc)), k, Color("5fd8ff") if k >= 1.0 else DIM)
	_text(bl + Vector2(0, 80 * sc), "%3d KM/H" % int(Vector2(p.vel.x, p.vel.z).length() * 3.6), fs, BONE)
	# weapons chain (bottom right)
	var br := Vector2(sz.x - 300 * sc, sz.y - 124 * sc)
	draw_rect(Rect2(br - Vector2(12, 22) * sc, Vector2(284, 136) * sc), PANEL)
	_text(br, "CHAIN FIRE  SPACE", fs, DIM)
	_text(br + Vector2(260 * sc, 0), "OVERHEAT" if p.overheat > 0.0 else "HEAT %d" % int(p.heat), fs,
		THREAT if p.overheat > 0.0 or p.heat > 75.0 else BONE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_bar(Rect2(br + Vector2(0, 8 * sc), Vector2(260 * sc, 5 * sc)), p.heat / 100.0, THREAT if p.heat > 75.0 else Color("ffb347"))
	for i in p.weapons.size():
		var w: Dictionary = p.weapons[i]
		var y := br.y + (38 + i * 28) * sc
		var ready: bool = w["cd"] <= 0.0
		var nxt: bool = i == p.chain_index
		_text(Vector2(br.x, y), ("▶ " if nxt else "  ") + String(w["name"]), fs, BONE if ready else DIM)
		_bar(Rect2(Vector2(br.x + 130 * sc, y - 9 * sc), Vector2(130 * sc, 7 * sc)), 1.0 - w["cd"] / w["cool"], BONE if ready else DIM)
	if callout_t > 0.0:
		_text(Vector2(0, c.y - 70 * sc), callout, int(20 * sc), Color(0.37, 0.85, 1.0, minf(1.0, callout_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, sz.x, Game.font_display)

func _draw_objective(sc: float) -> void:
	if objective == "":
		return
	var pos := Vector2(28, 36) * sc
	var w := 430.0 * sc
	draw_rect(Rect2(pos - Vector2(12, 26) * sc, Vector2(w, 86 * sc)), PANEL)
	draw_rect(Rect2(pos - Vector2(12, 26) * sc, Vector2(3 * sc, 86 * sc)), Color("ff4a5a"))
	_text(pos, "OPERATION DRY WASH", int(11 * sc), DIM)
	_text(pos + Vector2(0, 26 * sc), objective, int(19 * sc), BONE, HORIZONTAL_ALIGNMENT_LEFT, -1, Game.font_display)
	if objective_hint != "":
		_text(pos + Vector2(0, 48 * sc), objective_hint, int(12 * sc), Color("5fd8ff"))

func _draw_radio(sz: Vector2, sc: float) -> void:
	if current.is_empty():
		return
	var who: String = current["who"]
	var col := Game.color_of(who)
	var w := minf(760.0 * sc, sz.x - 40)
	var pos := Vector2((sz.x - w) * 0.5, sz.y - 200 * sc)
	var font := Game.font_body
	var fs := int(17 * sc)
	var lines := _wrap(current["text"], font, fs, w - 150 * sc)
	var h := (30 + lines.size() * 22) * sc
	draw_rect(Rect2(pos, Vector2(w, h)), PANEL)
	draw_rect(Rect2(pos, Vector2(3 * sc, h)), col)
	_text(pos + Vector2(14, 24) * sc, who, int(12 * sc), col)
	for i in 6:
		var bh := (3.0 + absf(sin(line_t * 13.0 + i * 1.7)) * 10.0) * sc if radio_player.playing else 2.0
		draw_rect(Rect2(pos + Vector2((14 + i * 6) * sc, 44 * sc - bh), Vector2(3 * sc, bh)), col)
	for i in lines.size():
		_text(pos + Vector2(130 * sc, (24 + i * 22) * sc), lines[i], fs, BONE, HORIZONTAL_ALIGNMENT_LEFT, -1, font)

func _wrap(s: String, font: Font, fs: int, width: float) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in s.split(" "):
		var trial := word if line == "" else line + " " + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out

func _draw_compass(sz: Vector2, sc: float) -> void:
	var cam_yaw: float = mission.cam_yaw
	var w := minf(520.0 * sc, sz.x * 0.45)
	var cx := sz.x * 0.5
	var y := 28.0 * sc
	var bearing := fposmod(-rad_to_deg(cam_yaw), 360.0)
	for dd in range(-60, 61, 5):
		var b := roundf(bearing / 5.0) * 5.0 + dd
		var px := cx + (b - bearing) / 60.0 * w * 0.5
		if absf(px - cx) > w * 0.5:
			continue
		var bb := int(fposmod(b, 360.0))
		var col := Color(BONE.r, BONE.g, BONE.b, 1.0 - absf(px - cx) / (w * 0.5) * 0.8)
		var major := bb % 45 == 0
		draw_line(Vector2(px, y), Vector2(px, y + (10.0 if major else 5.0) * sc), col, 1.4)
		if major:
			_text(Vector2(px - 20 * sc, y - 6 * sc), ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][bb / 45], int(11 * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 40 * sc)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 13 * sc), Vector2(cx - 5 * sc, y + 20 * sc), Vector2(cx + 5 * sc, y + 20 * sc)]), BONE)
	var wp = mission.waypoint
	if wp != null:
		var to: Vector3 = wp - mission.player.position
		var wb := fposmod(-rad_to_deg(atan2(-to.x, -to.z)), 360.0)
		var d := wrapf(wb - bearing, -180.0, 180.0)
		var px := cx + clampf(d, -60.0, 60.0) / 60.0 * w * 0.5
		draw_rect(Rect2(px - 4 * sc, y + 22 * sc, 8 * sc, 8 * sc), Color("5fd8ff"))

func _draw_world_markers(sz: Vector2, sc: float) -> void:
	var p: Mech = mission.player
	# waypoint
	var wp = mission.waypoint
	if wp != null:
		var world: Vector3 = wp + Vector3(0, 12, 0)
		var dist := Vector2(wp.x - p.position.x, wp.z - p.position.z).length()
		var s = _screen(world)
		var margin := 60.0 * sc
		var pos: Vector2
		var on := s != null and Rect2(Vector2(margin, margin), sz - Vector2(margin, margin) * 2.0).has_point(s)
		if on:
			pos = s
		else:
			var cam: Camera3D = mission.cam
			var local := cam.global_transform.affine_inverse() * world
			var dir := Vector2(local.x, -local.y).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.UP
			pos = sz * 0.5 + dir * minf(sz.x, sz.y) * 0.42
		var k := 10.0 * sc
		var col := Color("5fd8ff")
		draw_polyline(PackedVector2Array([pos + Vector2(0, -k), pos + Vector2(k, 0), pos + Vector2(0, k), pos + Vector2(-k, 0), pos + Vector2(0, -k)]), col, 2.0)
		_text(pos + Vector2(-60, 28) * sc, "%s  %dm" % [mission.waypoint_name, int(dist)], int(12 * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 120 * sc)
	# lancemates
	for m in mission.lance:
		var s = _screen(m.position + Vector3(0, 12.5, 0))
		if s == null:
			continue
		var col := Game.color_of(m.callsign)
		_text(s - Vector2(60, 0) * sc, m.callsign, int(11 * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 120 * sc)
		draw_rect(Rect2(s + Vector2(-4, 4) * sc, Vector2(8, 8) * sc), col)
	# drones: awareness brackets (no lock-on)
	for d in mission.drones:
		if not is_instance_valid(d) or not d.alive:
			continue
		var dist: float = d.position.distance_to(p.position)
		if dist > 420.0:
			continue
		var s = _screen(d.position)
		if s == null:
			continue
		var k := clampf(1400.0 / dist, 10.0, 34.0) * sc
		var col := THREAT
		if d.charging():
			col = Color(1, 0.9, 0.5) if int(mission.clock * 12.0) % 2 == 0 else THREAT
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var corner: Vector2 = s + q * k
			draw_line(corner, corner - Vector2(q.x * k * 0.45, 0), col, 1.6)
			draw_line(corner, corner - Vector2(0, q.y * k * 0.45), col, 1.6)
		var tag := "%dm" % int(dist)
		if d.invulnerable:
			tag = "DRILL"
		_text(s + Vector2(-50 * sc, k + 14 * sc), tag, int(11 * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 100 * sc)
		for i in d.assigned.size():
			var cs: String = d.assigned[i]
			_text(s + Vector2(-60 * sc, -k - (8 + i * 14) * sc), cs, int(10 * sc), Game.color_of(cs), HORIZONTAL_ALIGNMENT_CENTER, 120 * sc)

func _draw_threats(sz: Vector2, sc: float) -> void:
	var p: Mech = mission.player
	var c := sz * 0.5
	var any := false
	for s in mission.projectiles.sabots:
		var n: Node3D = s["node"]
		var to_p: Vector3 = p.position + Vector3(0, 6, 0) - n.position
		if s["done"] or to_p.length() > 180.0 or to_p.dot(s["vel"]) <= 0.0:
			continue
		any = true
		var sp = _screen(n.position)
		var margin := 40.0 * sc
		if sp != null and Rect2(Vector2(margin, margin), sz - Vector2(margin, margin) * 2.0).has_point(sp):
			var rr := (14.0 + 8.0 * absf(sin(mission.clock * 10.0))) * sc
			draw_arc(sp, rr, 0, TAU, 24, THREAT, 2.0)
		else:
			var cam: Camera3D = mission.cam
			var local := cam.global_transform.affine_inverse() * n.position
			var dir := Vector2(local.x, -local.y).normalized()
			var base := c + dir * 110.0 * sc
			var tip := c + dir * 138.0 * sc
			var side := Vector2(-dir.y, dir.x) * 10.0 * sc
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), THREAT)
	if any:
		_text(Vector2(0, c.y + 70 * sc), "INCOMING", int(14 * sc), THREAT, HORIZONTAL_ALIGNMENT_CENTER, sz.x)

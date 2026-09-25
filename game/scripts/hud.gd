class_name Hud
extends Control
## The pilot's ocular implant overlay + comms radio (voice lines with subtitles).
## Drawn into a SubViewport and projected through shaders/implant.gdshader (RGB split, scan, glitch).
## Cockpit instruments live on the MFDs (mfd.gd); this layer carries what the implant adds on top.

const IMPLANT := preload("res://shaders/implant.gdshader")
const INK := Color(0.78, 0.96, 1.0)
const DIM := Color(0.78, 0.96, 1.0, 0.45)
const FAINT := Color(0.78, 0.96, 1.0, 0.16)
const BONE := Color("e9e4d6")
const THREAT := Color("ff3b30")
const CYAN := Color("5fd8ff")
const HEAT := Color("ffb347")
const SHADOW := Color(0, 0, 0, 0.55)

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
var link := 0.0       # implant sync: 0 offline .. 1 fully linked
var glitch_t := 0.0
var fx_mat: ShaderMaterial

## Build the viewport + container that carry the overlay, add them to `parent`, return the Hud.
static func mount(parent: Node, m: Node) -> Hud:
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	box.add_child(vp)
	var h := Hud.new()
	vp.add_child(h)
	parent.add_child(box)
	h.fx_mat = ShaderMaterial.new()
	h.fx_mat.shader = IMPLANT
	box.material = h.fx_mat
	h.setup(m)
	return h

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
	glitch(0.6)

func glitch(k: float) -> void:
	glitch_t = maxf(glitch_t, k)

func show_callout(text: String) -> void:
	callout = text
	callout_t = 1.4

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	damage_t = maxf(0.0, damage_t - delta)
	callout_t = maxf(0.0, callout_t - delta)
	glitch_t = maxf(0.0, glitch_t - delta * 1.6)
	var vs := get_viewport_rect().size
	if size != vs:
		size = vs
	if fx_mat:
		var g := glitch_t
		if link < 1.0 and randf() < 0.04:
			g = maxf(g, 0.5)
		fx_mat.set_shader_parameter("glitch", g)
		fx_mat.set_shader_parameter("link", link)
	if not current.is_empty():
		line_t += delta
		if line_t > float(current["dur"]) + 1.0 and not radio_player.playing:
			_next_line()
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
## Text with a dark drop so thin implant glyphs read against bright sand.
func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	var f := font if font else Game.font_mono
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width <= 0.0:   # right-align on pos.x
		pos.x -= f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		align = HORIZONTAL_ALIGNMENT_LEFT
	draw_string(f, pos + Vector2(1, 1), s, align, width, size, Color(0, 0, 0, SHADOW.a * col.a))
	draw_string(f, pos, s, align, width, size, col)

func _line(a: Vector2, b: Vector2, col: Color, w := 1.5) -> void:
	draw_line(a + Vector2(1, 1), b + Vector2(1, 1), Color(0, 0, 0, 0.35 * col.a), w)
	draw_line(a, b, col, w)

func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w := 2.0) -> void:
	if absf(a1 - a0) < 0.001:
		return
	draw_arc(c + Vector2(1, 1), r, a0, a1, 32, Color(0, 0, 0, 0.35 * col.a), w)
	draw_arc(c, r, a0, a1, 32, col, w)

func _screen(world: Vector3) -> Variant:
	var cam: Camera3D = mission.cam
	if cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)

func _draw() -> void:
	var sz := size
	if sz.x < 320.0 or sz.y < 240.0:
		return
	var sc := clampf(sz.y / 900.0, 0.75, 1.6)
	if damage_t > 0.0:
		var a := damage_t * 0.9
		var e := 90.0 * sc
		draw_rect(Rect2(0, 0, sz.x, e), Color(0.8, 0.05, 0.02, a * 0.35))
		draw_rect(Rect2(0, sz.y - e, sz.x, e), Color(0.8, 0.05, 0.02, a * 0.35))
		draw_rect(Rect2(0, 0, e, sz.y), Color(0.8, 0.05, 0.02, a * 0.3))
		draw_rect(Rect2(sz.x - e, 0, e, sz.y), Color(0.8, 0.05, 0.02, a * 0.3))
	if link > 0.0:
		_draw_optic_frame(sz, sc)
	if link < 1.0:
		_draw_sync(sz, sc)
	_draw_objective(sc)
	_draw_radio(sz, sc)
	if not show_combat:
		return
	_draw_world_markers(sz, sc)
	_draw_compass(sz, sc)
	_draw_reticle(sz, sc)
	_draw_throttle_tape(sz, sc)
	_draw_threats(sz, sc)
	if callout_t > 0.0:
		_text(Vector2(0, sz.y * 0.5 - 110 * sc), callout, int(20 * sc), Color(0.37, 0.85, 1.0, minf(1.0, callout_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, sz.x, Game.font_display)

# ---------------------------------------------------------------- implant chrome
func _draw_optic_frame(sz: Vector2, sc: float) -> void:
	# corner arcs mark the edge of the implant's projection field
	var col := Color(INK.r, INK.g, INK.b, 0.22 * link)
	var m := 26.0 * sc
	var k := 70.0 * sc
	for q in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var corner := Vector2(lerpf(m, sz.x - m, q.x), lerpf(m, sz.y - m, q.y))
		var dx := 1.0 if q.x == 0.0 else -1.0
		var dy := 1.0 if q.y == 0.0 else -1.0
		draw_line(corner, corner + Vector2(dx * k, 0), col, 1.5)
		draw_line(corner, corner + Vector2(0, dy * k), col, 1.5)
		draw_line(corner + Vector2(dx * 6, dy * 6) * sc, corner + Vector2(dx * 18, dy * 6) * sc, col, 1.0)
	_text(Vector2(m + 6 * sc, sz.y - m - 8 * sc), "GIDEON · N-LINK %d%%" % int(link * 100.0), int(10 * sc), Color(INK.r, INK.g, INK.b, 0.4 * link))

func _draw_sync(sz: Vector2, sc: float) -> void:
	var c := sz * 0.5
	var col := INK
	var lines := ["OCULAR IMPLANT · SABLE-PATTERN v3", "NEURAL HANDSHAKE", "MOTOR CORTEX MAP", "SENSOR FUSION", "WEAPON SLAVE"]
	var shown := int(clampf(link, 0.0, 0.999) * lines.size()) + 1
	for i in mini(shown, lines.size()):
		var done := link * lines.size() > i + 1
		_text(Vector2(c.x - 170 * sc, c.y - 40 * sc + i * 18 * sc), lines[i], int(12 * sc), col if done else DIM)
		if i > 0:
			_text(Vector2(c.x + 170 * sc, c.y - 40 * sc + i * 18 * sc), "SYNC" if done else "····", int(12 * sc), col if done else DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var r := Rect2(c.x - 170 * sc, c.y + 60 * sc, 340 * sc, 3 * sc)
	draw_rect(r, FAINT)
	draw_rect(Rect2(r.position, Vector2(r.size.x * link, r.size.y)), INK)

func _draw_reticle(sz: Vector2, sc: float) -> void:
	var p: Mech = mission.player
	var c := sz * 0.5
	var hot := p.overheat > 0.0
	var rc := THREAT if hot else INK
	var r := 11.0 * sc
	_arc(c, r, 0, TAU, rc, 1.5)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
		_line(c + d * (r + 4 * sc), c + d * (r + 12 * sc), rc, 1.5)
	draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), rc)
	if hit_t > 0.0:
		var k := 8.0 * sc
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * k, c + d * k * 2.0, Color(1, 0.85, 0.5), 2.2)
	# heat arc (left) and armor arc (right) hug the reticle
	var R := 74.0 * sc
	var span := 0.62
	var hk := clampf(p.heat / 100.0, 0.0, 1.0)
	var hcol := THREAT if p.heat > 75.0 or hot else HEAT
	if hot and int(mission.clock * 6.0) % 2 == 0:
		hcol = BONE
	_arc(c, R, PI - span, PI + span, FAINT, 3.0)
	_arc(c, R, PI + span - 2.0 * span * hk, PI + span, hcol, 3.0)
	_line(c + Vector2(cos(PI + span * 0.5), sin(PI + span * 0.5)) * (R - 6 * sc), c + Vector2(cos(PI + span * 0.5), sin(PI + span * 0.5)) * (R + 6 * sc), THREAT, 1.5)
	_text(c + Vector2(-R * cos(span) - 8 * sc, R * sin(span) + 16 * sc), "SHUTDOWN" if hot else "HEAT %d" % int(p.heat), int(10 * sc), hcol, HORIZONTAL_ALIGNMENT_RIGHT)
	var ak := clampf(p.armor / 100.0, 0.0, 1.0)
	var acol := INK if p.armor > 35.0 else THREAT
	_arc(c, R, -span, span, FAINT, 3.0)
	_arc(c, R, span - 2.0 * span * ak, span, acol, 3.0)
	_text(c + Vector2(R * cos(span) + 8 * sc, R * sin(span) + 16 * sc), "ARM %d" % int(p.armor), int(10 * sc), acol)
	# weapon pips under the reticle: fill = recharge, bright = next in the chain
	var names := ["RAC", "LAS", "SRM"]
	var pw := 34.0 * sc
	var y := c.y + 58 * sc
	for i in p.weapons.size():
		var w: Dictionary = p.weapons[i]
		var x := c.x + (i - 1) * (pw + 8 * sc) - pw * 0.5
		var ready: bool = w["cd"] <= 0.0 and not hot
		var k := clampf(1.0 - w["cd"] / w["cool"], 0.0, 1.0)
		var col := INK if ready else DIM
		draw_rect(Rect2(x, y, pw, 3 * sc), FAINT)
		draw_rect(Rect2(x, y, pw * k, 3 * sc), col)
		_text(Vector2(x, y + 15 * sc), names[i], int(9 * sc), col if i == p.chain_index else DIM, HORIZONTAL_ALIGNMENT_CENTER, pw)
	# torso twist: where the legs point, relative to the view
	var tw := p.twist / Mech.TWIST_MAX
	var ty := c.y + 92 * sc
	var tw_w := 90.0 * sc
	_line(Vector2(c.x - tw_w, ty), Vector2(c.x + tw_w, ty), FAINT, 1.0)
	_line(Vector2(c.x, ty - 4 * sc), Vector2(c.x, ty + 4 * sc), DIM, 1.0)
	var lx := c.x - tw * tw_w
	draw_colored_polygon(PackedVector2Array([Vector2(lx, ty - 1 * sc), Vector2(lx - 5 * sc, ty + 7 * sc), Vector2(lx + 5 * sc, ty + 7 * sc)]), CYAN if absf(tw) < 0.98 else THREAT)
	if absf(p.twist) > 0.2:
		_text(Vector2(c.x - 60 * sc, ty + 20 * sc), "LEGS %s%d°" % ["R " if p.twist > 0.0 else "L ", int(absf(rad_to_deg(p.twist)))], int(9 * sc), DIM, HORIZONTAL_ALIGNMENT_CENTER, 120 * sc)

func _draw_throttle_tape(sz: Vector2, sc: float) -> void:
	var p: Mech = mission.player
	var c := sz * 0.5
	var x := c.x - 250 * sc
	var top := c.y - 90 * sc
	var h := 180.0 * sc
	var zero_y := top + h * 0.75
	_line(Vector2(x, top), Vector2(x, top + h), FAINT, 1.5)
	for i in 5:
		var yy := lerpf(zero_y, top, i / 4.0)
		_line(Vector2(x, yy), Vector2(x - (8 if i % 2 == 0 else 4) * sc, yy), DIM, 1.0)
	_line(Vector2(x, zero_y), Vector2(x, top + h), Color(THREAT.r, THREAT.g, THREAT.b, 0.4), 1.5)
	var sk := p.speed / Mech.RUN if p.speed >= 0.0 else p.speed / Mech.BACK
	var sy := zero_y - (zero_y - top) * sk if sk >= 0.0 else zero_y - (top + h - zero_y) * sk
	draw_rect(Rect2(x + 2 * sc, minf(sy, zero_y), 4 * sc, absf(zero_y - sy)), INK if sk >= 0.0 else THREAT)
	var tk := p.throttle
	var ty := zero_y - (zero_y - top) * tk if tk >= 0.0 else zero_y - (top + h - zero_y) * tk
	draw_colored_polygon(PackedVector2Array([Vector2(x + 8 * sc, ty), Vector2(x + 16 * sc, ty - 5 * sc), Vector2(x + 16 * sc, ty + 5 * sc)]), CYAN)
	_text(Vector2(x + 20 * sc, ty + 4 * sc), "%+d" % int(round(tk * 100.0)), int(10 * sc), CYAN)
	_text(Vector2(x - 70 * sc, top - 10 * sc), "%d KM/H" % int(absf(p.speed) * 3.6), int(13 * sc), INK, HORIZONTAL_ALIGNMENT_LEFT)
	if p.speed < -0.2:
		_text(Vector2(x - 70 * sc, top + h + 16 * sc), "REVERSE", int(10 * sc), THREAT)

func _draw_objective(sc: float) -> void:
	if objective == "":
		return
	var pos := Vector2(44, 58) * sc
	draw_rect(Rect2(pos - Vector2(12, 24) * sc, Vector2(2 * sc, 70 * sc)), Color("ff4a5a"))
	_text(pos, "OPERATION DRY WASH", int(10 * sc), DIM)
	_text(pos + Vector2(0, 24 * sc), objective, int(19 * sc), INK, HORIZONTAL_ALIGNMENT_LEFT, -1, Game.font_display)
	if objective_hint != "":
		_text(pos + Vector2(0, 44 * sc), objective_hint, int(12 * sc), CYAN)

func _draw_radio(sz: Vector2, sc: float) -> void:
	if current.is_empty():
		return
	var who: String = current["who"]
	var col := Game.color_of(who)
	# comms sit under the objective, top left, clear of the reticle and the dash
	var w := minf(600.0 * sc, sz.x * 0.5)
	var pos := Vector2(32 * sc, 138 * sc)
	var font := Game.font_body
	var fs := int(17 * sc)
	var lines := _wrap(current["text"], font, fs, w - 150 * sc)
	var h := (30 + lines.size() * 22) * sc
	draw_rect(Rect2(pos, Vector2(w, h)), Color(0.02, 0.04, 0.05, 0.45))
	draw_rect(Rect2(pos, Vector2(2 * sc, h)), col)
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
	var w := minf(460.0 * sc, sz.x * 0.4)
	var cx := sz.x * 0.5
	var y := 34.0 * sc
	var bearing := fposmod(-rad_to_deg(cam_yaw), 360.0)
	for dd in range(-60, 61, 5):
		var b := roundf(bearing / 5.0) * 5.0 + dd
		var px := cx + (b - bearing) / 60.0 * w * 0.5
		if absf(px - cx) > w * 0.5:
			continue
		var bb := int(fposmod(b, 360.0))
		var col := Color(INK.r, INK.g, INK.b, 0.9 - absf(px - cx) / (w * 0.5) * 0.75)
		var major := bb % 45 == 0
		_line(Vector2(px, y), Vector2(px, y + (9.0 if major else 4.0) * sc), col, 1.2)
		if major:
			_text(Vector2(px - 20 * sc, y - 6 * sc), ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][bb / 45], int(11 * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 40 * sc)
	_text(Vector2(cx - 30 * sc, y + 30 * sc), "%03d" % int(bearing), int(11 * sc), INK, HORIZONTAL_ALIGNMENT_CENTER, 60 * sc)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 11 * sc), Vector2(cx - 4 * sc, y + 17 * sc), Vector2(cx + 4 * sc, y + 17 * sc)]), INK)
	# legs heading on the tape
	var p: Mech = mission.player
	var lb := fposmod(-rad_to_deg(p.yaw), 360.0)
	var ld := wrapf(lb - bearing, -180.0, 180.0)
	var lx := cx + clampf(ld, -60.0, 60.0) / 60.0 * w * 0.5
	draw_rect(Rect2(lx - 1.5 * sc, y - 12 * sc, 3 * sc, 9 * sc), CYAN)
	var wp = mission.waypoint
	if wp != null:
		var to: Vector3 = wp - p.position
		var wb := fposmod(-rad_to_deg(atan2(-to.x, -to.z)), 360.0)
		var d := wrapf(wb - bearing, -180.0, 180.0)
		var px := cx + clampf(d, -60.0, 60.0) / 60.0 * w * 0.5
		var k := 5.0 * sc
		var q := Vector2(px, y + 24 * sc)
		draw_polyline(PackedVector2Array([q + Vector2(0, -k), q + Vector2(k, 0), q + Vector2(0, k), q + Vector2(-k, 0), q + Vector2(0, -k)]), CYAN, 1.5)
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
		var col := CYAN
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
		_text(Vector2(0, c.y - 150 * sc), "INCOMING", int(14 * sc), THREAT, HORIZONTAL_ALIGNMENT_CENTER, sz.x)

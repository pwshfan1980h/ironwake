class_name TacMap
extends Control
## Top-down tactical map. Time slows while open. Click a lancemate (or 1-3), then a drone to assign it.
## Right-click clears the selected lancemate's order.

const SLOW := 0.2

var mission: Node
var tex: ImageTexture
var selected: Mech = null
var hover: Object = null
var map_rect := Rect2()

func setup(m: Node) -> void:
	mission = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	tex = ImageTexture.create_from_image(mission.terrain.map_image)

func open() -> void:
	visible = true
	Engine.time_scale = SLOW
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if selected == null and mission.lance.size() > 0:
		selected = mission.lance[0]
	Sfx.play("ui", -6.0)

func close() -> void:
	visible = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.play("ui", -6.0, 0.8)

func _world_to_map(p: Vector3) -> Vector2:
	var s := Terrain.SIZE
	return map_rect.position + Vector2((p.x + s * 0.5) / s, (p.z + s * 0.5) / s) * map_rect.size

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _pick(pos: Vector2) -> Object:
	var best: Object = null
	var bd := 22.0
	for m in mission.lance:
		var d := pos.distance_to(_world_to_map(m.position))
		if d < bd:
			bd = d
			best = m
	for dr in mission.drones:
		if not is_instance_valid(dr) or not dr.alive:
			continue
		var d := pos.distance_to(_world_to_map(dr.position))
		if d < bd:
			bd = d
			best = dr
	return best

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = _pick(e.position)
	elif e is InputEventMouseButton and e.pressed:
		var hit := _pick(e.position)
		if e.button_index == MOUSE_BUTTON_LEFT:
			if hit is Mech:
				selected = hit
				Sfx.play("select", -6.0)
			elif hit is Drone and selected != null:
				mission.assign(selected, hit)
				Sfx.play("select", -4.0, 1.2)
		elif e.button_index == MOUSE_BUTTON_RIGHT and selected != null:
			mission.assign(selected, null)
		accept_event()

func select_index(i: int) -> void:
	if i < mission.lance.size():
		selected = mission.lance[i]
		Sfx.play("select", -6.0)

func _draw() -> void:
	var sz := size
	var sc := clampf(sz.y / 900.0, 0.75, 1.6)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.03, 0.03, 0.72))
	var side := minf(sz.x - 360.0 * sc, sz.y - 120.0 * sc)
	side = maxf(side, 240.0)
	map_rect = Rect2(Vector2(40 * sc, (sz.y - side) * 0.5), Vector2(side, side))
	draw_texture_rect(tex, map_rect, false, Color(1, 1, 1, 0.92))
	draw_rect(map_rect, Color(0.91, 0.89, 0.84, 0.5), false, 1.5)
	var font: Font = Game.font_mono
	var fs := int(12 * sc)
	# grid
	for i in range(1, 8):
		var x := map_rect.position.x + map_rect.size.x * i / 8.0
		var y := map_rect.position.y + map_rect.size.y * i / 8.0
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), Color(1, 1, 1, 0.06))
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), Color(1, 1, 1, 0.06))
	# route and waypoints
	var route: Array = mission.route_points
	for i in route.size():
		var a := _world_to_map(Vector3(route[i].x, 0, route[i].y))
		if i > 0:
			var b := _world_to_map(Vector3(route[i - 1].x, 0, route[i - 1].y))
			draw_dashed_line(b, a, Color(0.37, 0.85, 1.0, 0.45), 1.5, 6.0)
		var cur: bool = i == mission.waypoint_index
		draw_arc(a, (9.0 if cur else 6.0) * sc, 0, TAU, 20, Color("5fd8ff") if cur else Color(0.37, 0.85, 1.0, 0.5), 2.0)
		draw_string(font, a + Vector2(10, -8) * sc, mission.route_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * sc), Color("5fd8ff"))
	# drones
	for dr in mission.drones:
		if not is_instance_valid(dr) or not dr.alive:
			continue
		var p := _world_to_map(dr.position)
		var k := 7.0 * sc
		var col := Color("ff3b30")
		if hover == dr:
			draw_arc(p, 14.0 * sc, 0, TAU, 20, col, 2.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, k), p + Vector2(-k, k)]), col)
	# lance + orders
	for m in mission.lance:
		var p := _world_to_map(m.position)
		var col := Game.color_of(m.callsign)
		if m.ai_target != null and is_instance_valid(m.ai_target):
			draw_dashed_line(p, _world_to_map(m.ai_target.position), col, 2.0, 8.0)
		var k := 8.0 * sc
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, 0), p + Vector2(0, k), p + Vector2(-k, 0)]), col)
		if selected == m:
			draw_arc(p, 15.0 * sc, 0, TAU, 24, Color.WHITE, 2.0)
		elif hover == m:
			draw_arc(p, 13.0 * sc, 0, TAU, 24, col, 1.5)
		draw_string(font, p + Vector2(12, 4) * sc, m.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * sc), col)
	# player
	var pp := _world_to_map(mission.player.position)
	var f := Vector2(-sin(mission.player.yaw), -cos(mission.player.yaw))
	var r := Vector2(-f.y, f.x)
	var k2 := 10.0 * sc
	draw_colored_polygon(PackedVector2Array([pp + f * k2, pp - f * k2 * 0.6 + r * k2 * 0.7, pp - f * k2 * 0.6 - r * k2 * 0.7]), Color("ff4a5a"))
	draw_string(font, pp + Vector2(12, 4) * sc, "GIDEON", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * sc), Color("ff4a5a"))
	# side panel
	var px := map_rect.end.x + 32 * sc
	var y := map_rect.position.y + 20 * sc
	draw_string(Game.font_display, Vector2(px, y + 10 * sc), "TAC MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * sc), Color("e9e4d6"))
	draw_string(font, Vector2(px, y + 36 * sc), "TIME SLOWED · TAB TO CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.91, 0.89, 0.84, 0.5))
	y += 80 * sc
	for i in mission.lance.size():
		var m: Mech = mission.lance[i]
		var col := Game.color_of(m.callsign)
		var sel := selected == m
		draw_rect(Rect2(Vector2(px - 10 * sc, y - 18 * sc), Vector2(290 * sc, 44 * sc)), Color(1, 1, 1, 0.08 if sel else 0.03))
		if sel:
			draw_rect(Rect2(Vector2(px - 10 * sc, y - 18 * sc), Vector2(3 * sc, 44 * sc)), col)
		draw_string(font, Vector2(px, y), "%d  %s" % [i + 1, m.callsign], HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * sc), col)
		var order := "FOLLOWING GIDEON"
		if m.ai_target != null and is_instance_valid(m.ai_target):
			order = "ENGAGING DRONE · %dm" % int(m.position.distance_to(m.ai_target.position))
		draw_string(font, Vector2(px, y + 18 * sc), order, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.91, 0.89, 0.84, 0.7))
		y += 56 * sc
	y += 16 * sc
	for ln in ["CLICK A LANCEMATE, OR PRESS 1-3", "THEN CLICK A DRONE TO ASSIGN IT", "RIGHT-CLICK: FALL BACK TO FOLLOW"]:
		draw_string(font, Vector2(px, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("5fd8ff"))
		y += 20 * sc

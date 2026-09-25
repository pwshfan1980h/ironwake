extends Node
## Flow: title -> mission -> debrief -> (replay | title).
## Debug/deep links: `--mission` / `--play` user args, or #mission / #play in the web URL.

var current: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var url_hash := ""
	if OS.has_feature("web"):
		url_hash = str(JavaScriptBridge.eval("window.location.hash", true))
	if "--autopilot" in args:
		start_mission(true, true)
	elif "--play" in args or url_hash == "#play":
		start_mission(true)
	elif "--mission" in args or url_hash == "#mission":
		start_mission(false)
	else:
		show_title()
	for a in args:
		if a.begins_with("--shot="):
			_shots(a.substr(7))

## Debug: `--shot=<prefix>,<t1>,<t2>...` saves a screenshot at each time (seconds) then quits.
func _shots(spec: String) -> void:
	var parts := spec.split(",")
	var t0 := 0.0
	for i in range(1, parts.size()):
		var tt := float(parts[i])
		await get_tree().create_timer(tt - t0, true, false, true).timeout
		t0 = tt
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [parts[0], i])
	get_tree().quit()

func _swap(n: Node) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if current:
		current.queue_free()
	current = n
	add_child(n)

func show_title() -> void:
	var t: Node = preload("res://scripts/title.gd").new()
	t.start_requested.connect(func(): start_mission(false))
	_swap(t)

func start_mission(skip_intro: bool, autopilot := false) -> void:
	var m := Mission.new()
	m.skip_intro = skip_intro
	m.autopilot = autopilot
	m.restart.connect(func(): start_mission(true))
	m.quit_to_title.connect(show_title)
	_swap(m)

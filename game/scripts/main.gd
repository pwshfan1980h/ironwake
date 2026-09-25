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

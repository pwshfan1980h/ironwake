extends Node
## Global state: input map, fonts, roster, voice manifest.

const ROSTER := [
	{"callsign": "GIDEON", "name": "Gideon", "role": "Striker pilot · you",
		"color": Color("ff4a5a"),
		"bio": "The first recruit the Wake has taken in thirty years. Pilots Knife Cell Striker unit 27 through a neural implant."},
	{"callsign": "ANVIL", "name": "Col. Maren Hask", "role": "Commander · age 95",
		"color": Color("ffb347"),
		"bio": "Born in the battalion's field hospital. More machine than woman now. She still walks point."},
	{"callsign": "KESTREL", "name": "Lt. Ines Varro", "role": "Scout",
		"color": Color("5fd8ff"),
		"bio": "Sees everything first and says so. Has never been wrong about a ridgeline."},
	{"callsign": "RATCHET", "name": "Sgt. Dov Okafor", "role": "Engineer",
		"color": Color("8dffb0"),
		"bio": "Keeps four machines walking on the parts of forty. Talks to actuators. They listen."},
]

const STORY := [
	"Iron Wake was raised a hundred years ago to walk the ore convoys across the Harrow Basin. The convoys stopped. The contracts dried up. The battalion kept walking.",
	"Colonel Maren Hask was born in the Wake's field hospital ninety-five years ago. She has buried three generations of pilots and carries pieces of their machines in her own body.",
	"Now the Sable combine is pushing drone packs into the dry washes, and four machines are all that answer the roll. You are Gideon. Your first patrol drops at dusk.",
]

var font_display: Font
var font_mono: Font
var font_body: Font
var voice := {}   # id -> {who, text, dur}
var result := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	font_display = load("res://fonts/BigShouldersStencil-ExtraBold.ttf")
	font_mono = load("res://fonts/IBMPlexMono-Medium.ttf")
	font_body = load("res://fonts/IBMPlexSansCondensed-Regular.ttf")
	var f := FileAccess.open("res://assets/voice/lines.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if data is Array:
			for ln in data:
				voice[ln["id"]] = ln

func color_of(callsign: String) -> Color:
	for r in ROSTER:
		if r["callsign"] == callsign:
			return r["color"]
	return Color("e9e4d6")

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)

func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)

func _setup_input() -> void:
	_key("throttle_up", [KEY_W, KEY_UP])
	_key("throttle_down", [KEY_S, KEY_DOWN])
	_key("turn_left", [KEY_A, KEY_LEFT])
	_key("turn_right", [KEY_D, KEY_RIGHT])
	_key("all_stop", [KEY_X])
	_key("center_torso", [KEY_C])
	_key("fire", [KEY_SPACE])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_key("map", [KEY_TAB, KEY_M])
	_key("pause", [KEY_ESCAPE, KEY_P])
	_key("skip", [KEY_ENTER, KEY_SPACE, KEY_ESCAPE])
	_key("select_1", [KEY_1])
	_key("select_2", [KEY_2])
	_key("select_3", [KEY_3])

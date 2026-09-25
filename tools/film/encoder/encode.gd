extends Control
## Plays a PNG frame sequence + WAV so Godot's Movie Maker can write it out as .ogv.
##   godot --path tools/film/encoder --write-movie out.ogv --fixed-fps 24 -- <frames_dir> <audio.wav>

var frames: PackedStringArray
var dir := ""
var i := 0
var rect := TextureRect.new()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0]
	var list := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".png"))
	list.sort()
	frames = PackedStringArray(list)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(rect)
	var p := AudioStreamPlayer.new()
	p.stream = AudioStreamWAV.load_from_file(args[1])
	add_child(p)
	p.play()

func _process(_d: float) -> void:
	if i >= frames.size():
		get_tree().quit()
		return
	rect.texture = ImageTexture.create_from_image(Image.load_from_file(dir.path_join(frames[i])))
	i += 1

extends Node
## Procedural sound effects, synthesized once at startup into AudioStreamWAVs.

const RATE := 22050
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 20:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		pool.append(p)
	streams["step"] = _thump(0.45, 62.0, 24.0, 0.9, 0.35)
	streams["land"] = _thump(1.1, 55.0, 18.0, 1.0, 0.8)
	streams["rac"] = _crack(0.07, 0.55, 2200.0)
	streams["laser"] = _zap(0.35)
	streams["srm"] = _whoosh(0.7, 0.5, true)
	streams["boom"] = _boom(1.4)
	streams["charge"] = _charge(0.95)
	streams["hit"] = _clank(0.35)
	streams["release"] = _whoosh(0.5, 0.7, false)
	streams["ui"] = _blip(0.06, 880.0)
	streams["select"] = _blip(0.09, 1320.0)
	streams["alarm"] = _blip(0.18, 620.0)

func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p := pool[next]
	next = (next + 1) % pool.size()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()

## play with distance falloff from the listener
func play_at(name: String, pos: Vector3, listener: Vector3, vol_db := 0.0) -> void:
	var d := pos.distance_to(listener)
	var att := clampf(1.0 - d / 260.0, 0.0, 1.0)
	if att <= 0.02:
		return
	play(name, vol_db + linear_to_db(att * att))

# ---------------------------------------------------------------- synthesis
func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * RATE))
	return s

func _thump(dur: float, f0: float, f1: float, gain: float, noise: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, sqrt(k))
		ph += TAU * f / RATE
		var env := exp(-t * 7.0 / dur)
		lp += (randf_range(-1.0, 1.0) - lp) * 0.08
		var clank := 0.0
		if t > 0.04 and t < 0.14:
			clank = sin(TAU * 190.0 * t) * sin(TAU * 311.0 * t) * 0.25 * exp(-(t - 0.04) * 30.0)
		s[i] = (sin(ph) * gain + lp * noise * 3.0) * env + clank
	return _wav(s)

func _crack(dur: float, gain: float, fc: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var lp := 0.0
	var a := clampf(fc / RATE * 3.0, 0.05, 0.9)
	for i in s.size():
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * a
		s[i] = (lp * 1.4 + sin(TAU * 95.0 * t) * 0.5) * exp(-t * 55.0) * gain
	return _wav(s)

func _zap(dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 1800.0 - 1300.0 * (t / dur)
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		s[i] = (saw * 0.35 + sin(ph * 0.5) * 0.3) * exp(-t * 6.0) * (0.8 + 0.2 * sin(TAU * 60.0 * t))
	return _wav(s)

func _whoosh(dur: float, gain: float, rising: bool) -> AudioStreamWAV:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var a := lerpf(0.02, 0.25, k) if rising else lerpf(0.3, 0.03, k)
		lp += (randf_range(-1.0, 1.0) - lp) * a
		var env := sin(k * PI) * (1.0 - k * 0.3)
		s[i] = lp * env * gain * 2.2
	return _wav(s)

func _boom(dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.06
		lp2 += (randf_range(-1.0, 1.0) - lp2) * 0.35
		var env := exp(-t * 3.2)
		s[i] = (lp * 2.6 + sin(TAU * 42.0 * t) * 0.6) * env + lp2 * exp(-t * 18.0) * 0.5
	return _wav(s)

func _charge(dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		ph += TAU * lerpf(300.0, 1600.0, k * k) / RATE
		s[i] = sin(ph) * 0.22 * k * (0.7 + 0.3 * sin(TAU * 24.0 * t))
	return _wav(s)

func _clank(dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var m := sin(TAU * 240.0 * t) * sin(TAU * 377.0 * t) + sin(TAU * 1130.0 * t) * 0.3
		s[i] = (m * 0.6 + randf_range(-1.0, 1.0) * 0.3 * exp(-t * 40.0)) * exp(-t * 11.0)
	return _wav(s)

func _blip(dur: float, f: float) -> AudioStreamWAV:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * f * t) * 0.25 * minf(1.0, (dur - t) * 60.0)
	return _wav(s)

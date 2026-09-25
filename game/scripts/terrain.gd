class_name Terrain
extends Node3D
## Heightfield desert with a traversable wash along the patrol route.
## No physics: gameplay samples heights directly (sample) and uses `obstacles`.

const SIZE := 640.0
const RES := 2.5
const N := 257   # SIZE / RES + 1

var heights := PackedFloat32Array()
var obstacles: Array[Vector4] = []   # x, z, radius, top_y
var path: Array[Vector2] = []
var map_image: Image
var _dunes := FastNoiseLite.new()
var _ripple := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _mesa := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")

func generate(route: Array[Vector2], seed_value := 27) -> void:
	path = route
	_rng.seed = seed_value
	_dunes.seed = seed_value
	_dunes.frequency = 0.007
	_dunes.fractal_octaves = 3
	_ripple.seed = seed_value + 1
	_ripple.frequency = 0.045
	_ripple.fractal_octaves = 2
	_ridge.seed = seed_value + 2
	_ridge.frequency = 0.0045
	_ridge.fractal_octaves = 2
	_mesa.seed = seed_value + 3
	_mesa.frequency = 0.0065
	_mesa.fractal_octaves = 2
	heights.resize(N * N)
	for iz in N:
		var z := -SIZE * 0.5 + iz * RES
		for ix in N:
			var x := -SIZE * 0.5 + ix * RES
			heights[iz * N + ix] = _h(x, z)
	_build_mesh()
	_scatter()
	_build_map_image()

func _path_dist(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

func _h(x: float, z: float) -> float:
	var dunes := _dunes.get_noise_2d(x, z) * 6.0
	var ripple := _ripple.get_noise_2d(x, z) * 1.3
	var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
	var ridge := r * r * r * 18.0
	var m := _mesa.get_noise_2d(x, z)
	var mesa := smoothstep(0.22, 0.3, m) * 22.0 + smoothstep(0.38, 0.43, m) * 14.0
	var h := dunes + ripple + ridge + mesa
	# the wash: a shallow sandy channel along the patrol route
	var d := _path_dist(x, z)
	var k := smoothstep(22.0, 70.0, d)
	var floor_h := dunes * 0.45 + ripple * 0.8 - 2.0 * (1.0 - smoothstep(0.0, 22.0, d))
	h = lerpf(floor_h, h, k)
	# basin walls at the map edge
	var e := maxf(absf(x), absf(z))
	h += smoothstep(SIZE * 0.4, SIZE * 0.5, e) * 45.0
	return h

func sample(x: float, z: float) -> float:
	var gx := clampf((x + SIZE * 0.5) / RES, 0.0, N - 1.001)
	var gz := clampf((z + SIZE * 0.5) / RES, 0.0, N - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * N + ix
	return lerpf(lerpf(heights[i], heights[i + 1], fx), lerpf(heights[i + N], heights[i + N + 1], fx), fz)

func normal_at(x: float, z: float) -> Vector3:
	var e := RES
	return Vector3(sample(x - e, z) - sample(x + e, z), 2.0 * e, sample(x, z - e) - sample(x, z + e)).normalized()

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(N * N)
	norms.resize(N * N)
	for iz in N:
		for ix in N:
			var i := iz * N + ix
			var x := -SIZE * 0.5 + ix * RES
			var z := -SIZE * 0.5 + iz * RES
			verts[i] = Vector3(x, heights[i], z)
			var hl := heights[iz * N + maxi(ix - 1, 0)]
			var hr := heights[iz * N + mini(ix + 1, N - 1)]
			var hd := heights[maxi(iz - 1, 0) * N + ix]
			var hu := heights[mini(iz + 1, N - 1) * N + ix]
			norms[i] = Vector3(hl - hr, 2.0 * RES, hd - hu).normalized()
	idx.resize((N - 1) * (N - 1) * 6)
	var k := 0
	for iz in N - 1:
		for ix in N - 1:
			var a := iz * N + ix
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = a + N
			idx[k + 3] = a + 1; idx[k + 4] = a + N + 1; idx[k + 5] = a + N
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------------------------------------------------------------- scatter
static func rock_mesh(seed_value: int, detail := 1) -> ArrayMesh:
	## jittered icosphere, flat shaded
	var sph := SphereMesh.new()
	sph.radial_segments = 7 + detail * 2
	sph.rings = 4 + detail
	var arr := sph.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nz := FastNoiseLite.new()
	nz.seed = seed_value
	nz.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var disp := func(p: Vector3) -> Vector3:
		var q := p * (1.0 + nz.get_noise_3dv(p * 1.3) * 0.35)
		q.y *= 0.72
		if q.y < -0.1:
			q.y = -0.1 + (q.y + 0.1) * 0.3
		return q
	for t in range(0, ind.size(), 3):
		var a: Vector3 = disp.call(v[ind[t]])
		var b: Vector3 = disp.call(v[ind[t + 1]])
		var c: Vector3 = disp.call(v[ind[t + 2]])
		var n := (c - a).cross(b - a).normalized()
		for p in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()

func _mm(mesh: Mesh, mat: Material, xforms: Array, colors: Array, shadows := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _rock_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	return m

func _rand_on_ground(min_path: float, max_path: float, tries := 30) -> Vector3:
	for i in tries:
		var x := _rng.randf_range(-SIZE * 0.44, SIZE * 0.44)
		var z := _rng.randf_range(-SIZE * 0.44, SIZE * 0.44)
		var d := _path_dist(x, z)
		if d >= min_path and d <= max_path:
			return Vector3(x, sample(x, z), z)
	return Vector3.INF

func _scatter() -> void:
	var rock_cols := [Color("5a4336"), Color("6e5140"), Color("4a3a31"), Color("7a5c47")]
	# boulders: big ones block movement and shots
	for variant in 3:
		var mesh := rock_mesh(11 + variant, 1)
		var xf := []
		var cols := []
		for i in 70:
			var p := _rand_on_ground(14.0, 400.0)
			if p == Vector3.INF:
				continue
			var s := pow(_rng.randf(), 2.2) * 5.5 + 0.6
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * _rng.randf_range(0.8, 1.5), s * _rng.randf_range(0.6, 1.2), s))
			p.y -= s * 0.25
			xf.append(Transform3D(basis, p))
			cols.append(rock_cols[_rng.randi() % rock_cols.size()])
			if s > 1.8:
				obstacles.append(Vector4(p.x, p.z, s * 1.1, p.y + s * 0.9))
		_mm(mesh, _rock_mat(), xf, cols)
	# pebbles and grit: dense near the wash
	var peb := rock_mesh(40, 0)
	var xf2 := []
	var c2 := []
	for i in 5000:
		var ang := _rng.randf() * TAU
		var p := Vector3.INF
		if i < 3200 and path.size() > 1:
			var seg := _rng.randi() % (path.size() - 1)
			var a := path[seg].lerp(path[seg + 1], _rng.randf())
			var r := _rng.randf_range(0.0, 60.0)
			p = Vector3(a.x + cos(ang) * r, 0.0, a.y + sin(ang) * r)
		else:
			p = Vector3(_rng.randf_range(-280, 280), 0.0, _rng.randf_range(-280, 280))
		p.y = sample(p.x, p.z) - 0.05
		var s := _rng.randf_range(0.12, 0.5)
		xf2.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(s, s * 0.7, s)), p))
		c2.append(rock_cols[_rng.randi() % rock_cols.size()].lightened(_rng.randf_range(0.0, 0.2)))
	_mm(peb, _rock_mat(), xf2, c2, false)
	# dry scrub: crossed thin blades
	var scrub := _scrub_mesh()
	var xf3 := []
	var c3 := []
	for i in 900:
		var p := _rand_on_ground(4.0, 200.0, 8)
		if p == Vector3.INF:
			continue
		if normal_at(p.x, p.z).y < 0.85:
			continue
		var s := _rng.randf_range(0.5, 1.4)
		xf3.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.3), s)), p))
		c3.append(Color("5d5238").lerp(Color("8a7a52"), _rng.randf()))
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 1.0
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(scrub, sm, xf3, c3, false)
	# hoodoos: stacked strata towers along the wash edges
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.95
	var hoodoo := _hoodoo_mesh()
	var xf4 := []
	var c4 := []
	for i in 34:
		var p := _rand_on_ground(34.0, 120.0)
		if p == Vector3.INF:
			continue
		var s := _rng.randf_range(0.8, 1.8)
		xf4.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.6), s)), p - Vector3(0, 1, 0)))
		c4.append(Color("6a4a3a").lerp(Color("8a5f45"), _rng.randf()))
		obstacles.append(Vector4(p.x, p.z, 3.2 * s, p.y + 16.0 * s))
	_mm(hoodoo, hm, xf4, c4)

func _scrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		var a := k * TAU / 7.0 + randf() * 0.3
		var lean := Vector3(cos(a), 0, sin(a)) * 0.45
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var top := lean + Vector3(0, 0.9 + randf() * 0.4, 0)
		var n := side.cross(top).normalized()
		for p in [-side, side, top + side * 0.2]:
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()

func _hoodoo_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.0
	var r := 3.0
	for tier in 5:
		var h := randf_range(2.5, 4.0)
		var r2 := r * randf_range(0.72, 0.95)
		if tier == 4:
			r2 = r * 1.35   # cap rock
		var seg := 7
		for i in seg:
			var a0 := i * TAU / seg
			var a1 := (i + 1) * TAU / seg
			var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
			var q0 := Vector3(cos(a0) * r2, y + h, sin(a0) * r2)
			var q1 := Vector3(cos(a1) * r2, y + h, sin(a1) * r2)
			var n := (p1 - p0).cross(q0 - p0).normalized() * -1.0
			for p in [p0, p1, q0, p1, q1, q0]:
				st.set_normal(n)
				st.add_vertex(p)
			for p in [q0, q1, Vector3(0, y + h, 0)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
		y += h
		r = r2 if tier < 3 else r2 * 0.8
	return st.commit()

func _build_map_image() -> void:
	var s := 256
	map_image = Image.create(s, s, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	for py in s:
		for px in s:
			var x := -SIZE * 0.5 + (px + 0.5) * SIZE / s
			var z := -SIZE * 0.5 + (py + 0.5) * SIZE / s
			var h := sample(x, z)
			var n := normal_at(x, z)
			var shade := clampf(n.dot(light), 0.0, 1.0)
			var base := Color("3a2c24").lerp(Color("8a6a50"), clampf((h + 4.0) / 50.0, 0.0, 1.0))
			var c := base * (0.45 + 0.75 * shade)
			if fmod(h + 100.0, 6.0) < 0.35:
				c = c.lightened(0.12)   # contour lines
			map_image.set_pixel(px, py, c)

class_name MeshKit
extends RefCounted
## Procedural geometry accumulator.
## - Lofted grids get analytic finite-difference normals and automatic LOD index
##   buffers (row/column decimation of the same vertex buffer), which Godot then
##   selects by screen size, so LOD transitions are FOV-aware and pop-free.
## - Small detail parts can be flagged `detail` so they vanish in LOD1/LOD2.

const FLIP := true  # Godot's front faces are clockwise

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var idx := PackedInt32Array()
var lod1 := PackedInt32Array()
var lod2 := PackedInt32Array()

func is_empty() -> bool:
	return idx.is_empty()

func _tri(list: PackedInt32Array, a: int, b: int, c: int) -> void:
	if FLIP:
		list.append(a); list.append(c); list.append(b)
	else:
		list.append(a); list.append(b); list.append(c)

func _add_v(p: Vector3, n: Vector3, c: Color, uv: Vector2) -> int:
	verts.append(p)
	norms.append(n)
	cols.append(c)
	uvs.append(uv)
	return verts.size() - 1

## rows: Array of PackedVector3Array (all same length). i = row (length), j = column (around).
## Normals point along cross(dP/dj, dP/di) (so choose ordering accordingly), or are
## flipped with `flip_n`. closed = columns wrap around.
## color_fn(p: Vector3, n: Vector3) -> Color. uv: (row_param, col_param) in metres-ish.
func add_grid(rows: Array, closed: bool, color_fn: Callable, lod := true, flip_n := false, lod_levels := 2) -> void:
	var R := rows.size()
	if R < 2:
		return
	var C: int = (rows[0] as PackedVector3Array).size()
	var CC := C + 1 if closed else C
	var base := verts.size()
	# arc-length style uv
	var vacc := PackedFloat32Array()
	vacc.resize(R)
	vacc[0] = 0.0
	for i in range(1, R):
		vacc[i] = vacc[i - 1] + (rows[i][0] as Vector3).distance_to(rows[i - 1][0])
	for i in R:
		var row: PackedVector3Array = rows[i]
		var uacc := 0.0
		for jj in CC:
			var j := jj % C
			var p: Vector3 = row[j]
			if jj > 0:
				uacc += p.distance_to(row[(jj - 1) % C])
			# finite differences
			var jp: int
			var jm: int
			if closed:
				jp = (j + 1) % C
				jm = (j - 1 + C) % C
			else:
				jp = mini(j + 1, C - 1)
				jm = maxi(j - 1, 0)
			var ip := mini(i + 1, R - 1)
			var im := maxi(i - 1, 0)
			var tj: Vector3 = row[jp] - row[jm]
			var ti: Vector3 = (rows[ip][j] as Vector3) - (rows[im][j] as Vector3)
			var n := tj.cross(ti)
			if n.length_squared() < 1e-14:
				# degenerate (pole); try neighbour row
				var i2 := ip if ip != i else im
				tj = (rows[i2][jp] as Vector3) - (rows[i2][jm] as Vector3)
				n = tj.cross(ti)
			n = n.normalized()
			if flip_n:
				n = -n
			_add_v(p, n, color_fn.call(p, n), Vector2(uacc, vacc[i]))
	# indices (winding follows the chosen normal side)
	var full_rows := range(R)
	var full_cols := range(CC)
	_emit_grid(idx, base, CC, full_rows, full_cols, flip_n, color_fn)
	if lod:
		_emit_grid(lod1, base, CC, _decimate(R, 2), _decimate(CC, 2), flip_n)
		if lod_levels >= 2:
			_emit_grid(lod2, base, CC, _decimate(R, 4), _decimate(CC, 4), flip_n)
	else:
		_emit_grid(lod1, base, CC, full_rows, full_cols, flip_n)
		_emit_grid(lod2, base, CC, full_rows, full_cols, flip_n)

func _decimate(n: int, step: int) -> Array:
	var out := []
	var i := 0
	while i < n - 1:
		out.append(i)
		i += step
	out.append(n - 1)
	if out.size() < 2:
		return [0, n - 1]
	return out

func _emit_grid(list: PackedInt32Array, base: int, cc: int, rsel: Array, csel: Array, rev := false, refine_fn := Callable()) -> void:
	for a in range(rsel.size() - 1):
		var i0: int = rsel[a]
		var i1: int = rsel[a + 1]
		for b in range(csel.size() - 1):
			var j0: int = csel[b]
			var j1: int = csel[b + 1]
			var v00 := base + i0 * cc + j0
			var v01 := base + i0 * cc + j1
			var v10 := base + i1 * cc + j0
			var v11 := base + i1 * cc + j1
			# outward normal = cross(dj, di): triangle (v00, v01, v10) has right-hand normal (dj x di)
			if rev:
				_tri_refined(list, v00, v10, v01, refine_fn)
				_tri_refined(list, v01, v10, v11, refine_fn)
			else:
				_tri_refined(list, v00, v01, v10, refine_fn)
				_tri_refined(list, v01, v11, v10, refine_fn)

## Livery is painted per vertex. Where neighbouring vertices carry very different paint
## (a stripe or camo edge crosses the triangle) the triangle is split into a small
## barycentric lattice and re-painted, so the edge resolves crisply instead of smearing or
## stair-stepping. Sub-vertices lie exactly on the parent triangle, so no cracks appear.
const REFINE_K := 4
const REFINE_THRESHOLD := 0.06

func _col_dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) * 0.5

func _tri_refined(list: PackedInt32Array, a: int, b: int, c: int, refine_fn: Callable) -> void:
	if not refine_fn.is_valid():
		_tri(list, a, b, c)
		return
	var ca := cols[a]
	var cb := cols[b]
	var cc2 := cols[c]
	if maxf(_col_dist(ca, cb), maxf(_col_dist(cb, cc2), _col_dist(ca, cc2))) < REFINE_THRESHOLD:
		_tri(list, a, b, c)
		return
	var k := REFINE_K
	var grid := {}
	for i in range(k + 1):
		for j in range(k + 1 - i):
			var w0 := float(k - i - j) / k
			var w1 := float(i) / k
			var w2 := float(j) / k
			if i == 0 and j == 0:
				grid[Vector2i(i, j)] = a
			elif i == k:
				grid[Vector2i(i, j)] = b
			elif j == k:
				grid[Vector2i(i, j)] = c
			else:
				var pos := verts[a] * w0 + verts[b] * w1 + verts[c] * w2
				var nrm := (norms[a] * w0 + norms[b] * w1 + norms[c] * w2).normalized()
				var uv := uvs[a] * w0 + uvs[b] * w1 + uvs[c] * w2
				grid[Vector2i(i, j)] = _add_v(pos, nrm, refine_fn.call(pos, nrm), uv)
	for i in range(k):
		for j in range(k - i):
			_tri(list, grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i, j + 1)])
			if i + j < k - 1:
				_tri(list, grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)])

## Flat polygon fan cap. ring ordered; normal given explicitly (outward).
func add_cap(center: Vector3, ring: PackedVector3Array, n: Vector3, color_fn: Callable, detail := false) -> void:
	var base := verts.size()
	var c0 := _add_v(center, n, color_fn.call(center, n), Vector2.ZERO)
	for p in ring:
		_add_v(p, n, color_fn.call(p, n), Vector2(p.x, p.z))
	var cnt := ring.size()
	for k in cnt:
		var a := base + 1 + k
		var b := base + 1 + (k + 1) % cnt
		# decide winding using normal
		var geo := (verts[a] - center).cross(verts[b] - center)
		var lists := [idx] if detail else [idx, lod1, lod2]
		for l in lists:
			if geo.dot(n) >= 0.0:
				_tri(l, c0, a, b)
			else:
				_tri(l, c0, b, a)

## Single triangle with explicit outward normal (auto winding)
func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, detail := false, n_hint := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n_hint != Vector3.ZERO and n.dot(n_hint) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var i0 := _add_v(a, n, color, Vector2(a.x, a.z))
	var i1 := _add_v(b, n, color, Vector2(b.x, b.z))
	var i2 := _add_v(c, n, color, Vector2(c.x, c.z))
	var lists := [idx] if detail else [idx, lod1, lod2]
	for l in lists:
		_tri(l, i0, i1, i2)

func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, detail := false, n_hint := Vector3.ZERO) -> void:
	add_triangle(a, b, c, color, detail, n_hint)
	add_triangle(a, c, d, color, detail, n_hint)

## Oriented box: xf maps unit box (-0.5..0.5) to world.
func add_box(xf: Transform3D, color: Color, detail := false) -> void:
	var c := [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)]]
	for f in faces:
		var n: Vector3 = (xf.basis * (f[4] as Vector3)).normalized()
		add_quad(xf * (c[f[0]] as Vector3), xf * (c[f[1]] as Vector3), xf * (c[f[2]] as Vector3), xf * (c[f[3]] as Vector3), color, detail, n)

## Cylinder / tube from a to b.
func add_cylinder(a: Vector3, b: Vector3, r0: float, r1: float, segs: int, color_fn: Callable, caps := true, detail := false) -> void:
	var axis := b - a
	var L := axis.length()
	if L < 1e-6:
		return
	var z := axis / L
	var x := z.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = z.cross(Vector3.RIGHT)
	x = x.normalized()
	var y := x.cross(z).normalized()
	var ring_a := PackedVector3Array()
	var ring_b := PackedVector3Array()
	for k in segs:
		var t := TAU * float(k) / segs
		var d := x * cos(t) + y * sin(t)
		ring_a.append(a + d * r0)
		ring_b.append(b + d * r1)
	var rows := [ring_a, ring_b]
	# ordering: columns around (x->y), rows along z: cross(dj, di) = (y dir) x z = outward x
	if detail:
		var base_lod1 := lod1.size()
		var base_lod2 := lod2.size()
		add_grid(rows, true, color_fn, false)
		lod1.resize(base_lod1)
		lod2.resize(base_lod2)
	else:
		add_grid(rows, true, color_fn, segs >= 8)
	if caps:
		if r0 > 0.0:
			add_cap(a, ring_a, -z, color_fn, detail)
		if r1 > 0.0:
			add_cap(b, ring_b, z, color_fn, detail)

## Surface of revolution. profile: Array of Vector2(axial, radius). Axis frame: origin + basis (z = axis).
func add_lathe(profile: Array, origin: Vector3, basis: Basis, segs: int, color_fn: Callable, lod := true, rx := 1.0, ry := 1.0) -> void:
	var rows := []
	for pr in profile:
		var v2: Vector2 = pr
		var ring := PackedVector3Array()
		for k in segs:
			var t := TAU * float(k) / segs
			var lp := Vector3(cos(t) * v2.y * rx, sin(t) * v2.y * ry, v2.x)
			ring.append(origin + basis * lp)
		rows.append(ring)
	add_grid(rows, true, color_fn, lod)

func add_ellipsoid(center: Vector3, radii: Vector3, segs: int, rings: int, color_fn: Callable, basis := Basis(), detail := false) -> void:
	var rows := []
	for i in rings + 1:
		var phi := PI * float(i) / rings  # 0 top? use along z axis
		var ring := PackedVector3Array()
		var rz := -cos(phi)
		var rr := sin(phi)
		for k in segs:
			var t := TAU * float(k) / segs
			var lp := Vector3(cos(t) * rr * radii.x, sin(t) * rr * radii.y, rz * radii.z)
			ring.append(center + basis * lp)
		rows.append(ring)
	if detail:
		var b1 := lod1.size()
		var b2 := lod2.size()
		add_grid(rows, true, color_fn, false)
		lod1.resize(b1)
		lod2.resize(b2)
	else:
		add_grid(rows, true, color_fn, true)

## translate every vertex (used to express meshes relative to a hinge pivot)
func offset(o: Vector3) -> void:
	for i in verts.size():
		verts[i] = verts[i] + o

func append_to(mesh: ArrayMesh, material: Material, lod_edge1 := 0.012, lod_edge2 := 0.035) -> void:
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var lods := {}
	if lod1.size() > 0 and lod1.size() < idx.size():
		lods[lod_edge1] = lod1
	if lod2.size() > 0 and lod2.size() < lod1.size():
		lods[lod_edge2] = lod2
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

static func const_color(c: Color) -> Callable:
	return func(_p: Vector3, _n: Vector3) -> Color: return c

func tri_count() -> int:
	return idx.size() / 3

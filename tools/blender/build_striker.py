"""IRON WAKE - procedural Striker (#27) + cockpit generator.

Usage (headless):
  blender -b -P tools/blender/build_striker.py -- <A|B|C> <out_dir> [--render]

Outputs:
  <out_dir>/striker_<V>.glb   mech, one mesh per pivot, named pivots for animation
  <out_dir>/cockpit_<V>.glb   cockpit shell, eye at origin looking -Y (glTF: -Z)
  <out_dir>/striker_<V>.png   optional hero still (Cycles)

Conventions (Blender space, Z up, mech faces -Y, 1 unit = 1 m):
  pivots:   root, pelvis, torso, hip_L/R, knee_L/R, ankle_L/R,
            shoulder_L/R, elbow_L/R, gatling_spin, cockpit_cam
  L = +X (mech's own left). All pivots unrotated in rest pose.
  material slots are names only; the runtime swaps in the art-direction
  palette by slot name (ARMOR gets the camo shader).
"""
import bpy, bmesh, math, sys, os, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VAR = argv[0] if argv else "A"
OUT = argv[1] if len(argv) > 1 else "."
RENDER = "--render" in argv
HERE = os.path.dirname(os.path.abspath(__file__))
PAL = json.load(open(os.path.join(HERE, "palettes.json")))[VAR]

SHAPE = {
    # bevel width, bevel segments, top taper, bulk, smooth shading, bolts, pod scale
    "A": dict(bevel=0.07, seg=2, taper=0.06, bulk=1.00, smooth=True, bolts=True, pod=1.00),
    "B": dict(bevel=0.15, seg=3, taper=0.00, bulk=1.12, smooth=True, bolts=True, pod=1.18),
    "C": dict(bevel=0.05, seg=1, taper=0.22, bulk=0.90, smooth=False, bolts=False, pod=0.88),
}[VAR]
B = SHAPE["bulk"]

MATS = ["ARMOR", "ARMOR_ALT", "FRAME", "TRIM", "BRASS", "GLASS", "LAMP", "BARREL", "DARK"]
CP_MATS = ["CP_PANEL", "CP_FRAME", "CP_TRIM", "DARK", "LAMP", "BARREL", "GLASS",
           "SCREEN_L", "SCREEN_C", "SCREEN_R"]


def hex2rgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- materials
def make_mat(name, color, metal=0.0, rough=0.6, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*hex2rgb(color), 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*hex2rgb(color), 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def camo_nodes(m, cols):
    """Render-only digital camo: snapped object coords -> noise -> 3 stops."""
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    snap = nt.nodes.new("ShaderNodeVectorMath"); snap.operation = "SNAP"
    snap.inputs[1].default_value = (0.32, 0.32, 0.32)
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.55
    ramp = nt.nodes.new("ShaderNodeValToRGB"); ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (*hex2rgb(cols[0]), 1)
    e[1].position, e[1].color = 0.47, (*hex2rgb(cols[1]), 1)
    e3 = e.new(0.58); e3.color = (*hex2rgb(cols[2]), 1)
    nt.links.new(tc.outputs["Object"], snap.inputs[0])
    nt.links.new(snap.outputs[0], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])


def build_mats():
    p = PAL
    mats = {
        "ARMOR": make_mat("ARMOR", p["camo"][0], 0.15, 0.62),
        "ARMOR_ALT": make_mat("ARMOR_ALT", p["armor_alt"], 0.15, 0.58),
        "FRAME": make_mat("FRAME", p["frame"], 0.7, 0.5),
        "TRIM": make_mat("TRIM", p["trim"], 0.1, 0.55),
        "BRASS": make_mat("BRASS", p["brass"], 0.9, 0.38),
        "GLASS": make_mat("GLASS", p["glass"], 0.0, 0.1, emit=3.0),
        "LAMP": make_mat("LAMP", p["lamp"], 0.0, 0.3, emit=6.0),
        "BARREL": make_mat("BARREL", p["barrel"], 0.95, 0.3),
        "DARK": make_mat("DARK", p["dark"], 0.3, 0.8),
        "DECAL": make_mat("DECAL", "#e8e4d8", 0.0, 0.7),
        "CP_PANEL": make_mat("CP_PANEL", p["cp_panel"], 0.3, 0.6),
        "CP_FRAME": make_mat("CP_FRAME", p["cp_frame"], 0.6, 0.5),
        "CP_TRIM": make_mat("CP_TRIM", p["cp_trim"], 0.1, 0.5),
        "SCREEN_L": make_mat("SCREEN_L", p["screen"], 0, 0.2, emit=1.5),
        "SCREEN_C": make_mat("SCREEN_C", p["screen"], 0, 0.2, emit=1.5),
        "SCREEN_R": make_mat("SCREEN_R", p["screen"], 0, 0.2, emit=1.5),
    }
    if VAR != "B":
        camo_nodes(mats["ARMOR"], p["camo"])
    return mats


# ---------------------------------------------------------------- geometry
class Part:
    """Accumulates primitives for one pivot into a single multi-material mesh."""

    def __init__(self, name, world, parent=None, slots=MATS):
        self.name, self.world, self.parent, self.slots = name, Vector(world), parent, slots
        self.bm = bmesh.new()
        self.obj = None

    def _merge(self, tmp, mat, smooth):
        idx = self.slots.index(mat)
        for f in tmp.faces:
            f.material_index = idx
            f.smooth = smooth
        for e in tmp.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0) > 0.62:
                e.smooth = False
        bmesh.ops.translate(tmp, verts=tmp.verts, vec=-self.world)
        me = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(me); tmp.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def box(self, size, center, mat="ARMOR", bevel=None, taper=None, seg=None, rot=None):
        sx, sy, sz = size
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        t = SHAPE["taper"] if taper is None else taper
        for v in tmp.verts:
            v.co.x *= sx; v.co.y *= sy; v.co.z *= sz
            if t and v.co.z > 0:
                v.co.x *= (1 - t); v.co.y *= (1 - t * 0.5)
        bv = SHAPE["bevel"] if bevel is None else bevel
        bv = min(bv, min(size) * 0.3)
        if bv > 0.001:
            bmesh.ops.bevel(tmp, geom=tmp.edges[:], offset=bv, offset_type="OFFSET",
                            segments=SHAPE["seg"] if seg is None else seg,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
        if rot:
            bmesh.ops.rotate(tmp, verts=tmp.verts, matrix=Matrix.Rotation(rot[1], 3, rot[0]))
        bmesh.ops.translate(tmp, verts=tmp.verts, vec=Vector(center))
        self._merge(tmp, mat, SHAPE["smooth"])

    def cyl(self, r, depth, center, axis="Z", mat="FRAME", seg=16, r2=None):
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r, radius2=r if r2 is None else r2, depth=depth)
        if axis == "X":
            bmesh.ops.rotate(tmp, verts=tmp.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
        elif axis == "Y":
            bmesh.ops.rotate(tmp, verts=tmp.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.translate(tmp, verts=tmp.verts, vec=Vector(center))
        self._merge(tmp, mat, True)

    def bolts(self, center, w, h, face="-Y", inset=0.1, r=0.045):
        if not SHAPE["bolts"]:
            return
        c = Vector(center)
        for a in (-1, 1):
            for b in (-1, 1):
                if face in ("-Y", "+Y"):
                    off = Vector((a * (w / 2 - inset), 0, b * (h / 2 - inset)))
                    self.cyl(r, 0.06, c + off, "Y", "BRASS", seg=8)
                elif face in ("-X", "+X"):
                    off = Vector((0, a * (w / 2 - inset), b * (h / 2 - inset)))
                    self.cyl(r, 0.06, c + off, "X", "BRASS", seg=8)
                else:
                    off = Vector((a * (w / 2 - inset), b * (h / 2 - inset), 0))
                    self.cyl(r, 0.06, c + off, "Z", "BRASS", seg=8)

    def build(self, coll):
        me = bpy.data.meshes.new(self.name + "_mesh")
        self.bm.to_mesh(me); self.bm.free()
        for s in self.slots:
            me.materials.append(bpy.data.materials[s])
        piv = bpy.data.objects.new(self.name, None)
        piv.empty_display_size = 0.25
        coll.objects.link(piv)
        if self.parent:
            piv.parent = self.parent.obj
            piv.location = self.world - self.parent.world
        else:
            piv.location = self.world
        ob = bpy.data.objects.new(self.name + "_mesh", me)
        coll.objects.link(ob)
        ob.parent = piv
        self.obj = piv
        return piv


def decal(coll, name, part, center, right, up, w, h, mat="DECAL"):
    c, r, u = Vector(center), Vector(right), Vector(up)
    me = bpy.data.meshes.new(name)
    pts = [c - r * w / 2 - u * h / 2, c + r * w / 2 - u * h / 2,
           c + r * w / 2 + u * h / 2, c - r * w / 2 + u * h / 2]
    me.from_pydata([p - part.world for p in pts], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for i, l in enumerate(me.loops):
        uv.data[i].uv = [(0, 0), (1, 0), (1, 1), (0, 1)][l.vertex_index]
    me.materials.append(bpy.data.materials[mat])
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = part.obj


# ---------------------------------------------------------------- the mech
def build_striker():
    coll = bpy.context.scene.collection
    P = {}
    root = P["root"] = Part("root", (0, 0, 0))
    pel = P["pelvis"] = Part("pelvis", (0, 0, 5.3), root)
    tor = P["torso"] = Part("torso", (0, 0, 5.9), pel)

    # pelvis
    pel.box((1.5 * B, 1.1, 0.8), (0, 0, 5.35), "FRAME")
    pel.box((1.0 * B, 0.35, 0.95), (0, -0.62, 5.15), "ARMOR")
    pel.bolts((0, -0.8, 5.15), 1.0 * B, 0.95)
    pel.box((1.25 * B, 0.3, 0.75), (0, 0.62, 5.2), "ARMOR_ALT")
    pel.cyl(0.58, 0.5, (0, 0, 5.85), "Z", "FRAME", seg=20)
    pel.cyl(0.66, 0.12, (0, 0, 5.62), "Z", "DARK", seg=20)

    # legs
    LB = B * 1.2
    for s, tag in ((1, "L"), (-1, "R")):
        x = s * 1.0 * LB
        hip = P["hip_" + tag] = Part("hip_" + tag, (x, 0, 5.3), pel)
        hip.cyl(0.45, 0.6, (x, 0, 5.3), "X", "FRAME", seg=20)
        hip.cyl(0.3, 0.64, (x, 0, 5.3), "X", "BARREL", seg=16)
        hip.box((0.26, 1.15, 1.05), (x + s * 0.44 * LB, 0, 5.2), "ARMOR")
        hip.bolts((x + s * 0.58 * LB, 0, 5.2), 1.15, 1.05, "+X")
        hip.box((0.72 * LB, 0.8 * LB, 2.0), (x, 0, 4.1), "FRAME", taper=0.0)
        hip.box((0.82 * LB, 0.3, 1.65), (x, -0.52 * LB, 4.25), "ARMOR")
        hip.bolts((x, -0.68 * LB, 4.25), 0.82 * LB, 1.65)
        hip.box((0.2, 0.92 * LB, 1.45), (x + s * 0.44 * LB, 0, 4.2), "ARMOR_ALT")
        hip.cyl(0.17, 0.9, (x, 0.5 * LB, 4.55), "Z", "FRAME", seg=12)
        hip.cyl(0.1, 1.7, (x, 0.5 * LB, 3.95), "Z", "BARREL", seg=10)

        knee = P["knee_" + tag] = Part("knee_" + tag, (x, 0, 2.9), hip)
        knee.cyl(0.42, 0.82, (x, 0, 2.9), "X", "FRAME", seg=20)
        knee.box((0.78 * LB, 0.5, 0.85), (x, -0.5 * LB, 2.98), "ARMOR")
        knee.box((0.66 * LB, 0.76 * LB, 2.0), (x, 0, 1.75), "FRAME", taper=0.0)
        knee.box((0.84 * LB, 0.3, 1.85), (x, -0.46 * LB, 1.8), "ARMOR", taper=-0.08)
        knee.bolts((x, -0.62 * LB, 1.8), 0.84 * LB, 1.85)
        knee.box((0.72 * LB, 0.52, 1.2), (x, 0.44 * LB, 2.05), "ARMOR_ALT")
        knee.box((0.86 * LB, 0.06, 0.16), (x, -0.63 * LB, 2.45), "TRIM", bevel=0.01)
        knee.cyl(0.08, 1.3, (x, 0.62 * LB, 1.3), "Z", "BARREL", seg=10)
        knee.cyl(0.14, 0.6, (x, 0.62 * LB, 1.75), "Z", "FRAME", seg=12)

        ank = P["ankle_" + tag] = Part("ankle_" + tag, (x, 0, 0.55), knee)
        ank.cyl(0.3, 0.72, (x, 0, 0.6), "X", "FRAME", seg=16)
        ank.box((1.0 * LB, 1.75, 0.45), (x, -0.25, 0.25), "FRAME", taper=0.0)
        ank.box((1.08 * LB, 0.75, 0.36), (x, -0.98, 0.3), "ARMOR")
        ank.box((0.72 * LB, 0.5, 0.42), (x, 0.72, 0.26), "ARMOR_ALT")
        ank.box((0.82 * LB, 0.8, 0.34), (x, -0.12, 0.62), "ARMOR")
        for dx in (-0.3, 0.3):  # toe claws
            ank.box((0.24, 0.45, 0.22), (x + dx * LB, -1.45, 0.14), "FRAME", taper=0.2)

    # torso
    tor.box((1.6 * B, 1.5, 0.8), (0, 0, 6.25), "FRAME", taper=0.0)
    tor.box((2.3 * B, 2.0, 2.0), (0, 0.1, 7.2), "ARMOR")
    tor.bolts((0, -0.91, 7.2), 2.3 * B, 2.0)
    tor.box((1.32, 1.1, 0.95), (0, -1.2, 7.45), "ARMOR_ALT")
    tor.box((0.96, 0.08, 0.2), (0, -1.74, 7.6), "GLASS", bevel=0.02)
    tor.box((1.25, 0.28, 0.18), (0, -1.68, 7.82), "FRAME", taper=0.0)
    tor.box((1.1, 0.12, 0.3), (0, -1.72, 7.2), "DARK", taper=0.0)
    for sx in (-1, 1):
        cx = sx * 1.55 * B
        tor.box((1.0 * B, 1.8, 1.7), (cx, 0.05, 7.3), "ARMOR")
        tor.bolts((cx, -0.86, 7.3), 1.0 * B, 1.7)
        for i in range(3):  # chest vents
            tor.box((0.7 * B, 0.06, 0.07), (cx, -0.87, 6.85 + i * 0.16), "DARK", bevel=0.0)
        tor.box((0.12, 0.06, 0.12), (cx + sx * 0.3, -0.88, 7.95), "LAMP", bevel=0.01)
    tor.box((1.8 * B, 0.9, 1.6), (0, 1.4, 7.1), "FRAME")
    for i in range(4):
        tor.box((1.5 * B, 0.06, 0.1), (0, 1.87, 6.6 + i * 0.3), "DARK", bevel=0.0)
    tor.cyl(0.22, 0.9, (0.55, 1.5, 8.1), "Z", "FRAME", seg=12)   # exhaust stacks
    tor.cyl(0.22, 0.9, (-0.55, 1.5, 8.1), "Z", "FRAME", seg=12)
    # sensor head + antennas
    tor.box((0.5, 0.55, 0.45), (0.38, -0.65, 8.43), "FRAME")
    tor.cyl(0.14, 0.12, (0.38, -0.95, 8.43), "Y", "LAMP", seg=14)
    tor.cyl(0.03, 2.4, (-0.6, 0.7, 9.35), "Z", "FRAME", seg=6)
    tor.cyl(0.03, 1.7, (0.75, 0.9, 9.0), "Z", "FRAME", seg=6)
    tor.cyl(0.07, 0.25, (-0.6, 0.7, 8.25), "Z", "BRASS", seg=8)
    # missile pod over right shoulder
    pk = SHAPE["pod"]
    px, pz = -1.7 * B, 8.75
    tor.box((1.15 * pk, 1.45 * pk, 0.95 * pk), (px, 0.2, pz), "ARMOR_ALT", taper=0.0)
    tor.box((0.06, 1.2 * pk, 0.6 * pk), (px - 0.6 * pk, 0.2, pz), "TRIM", bevel=0.01)
    for i in range(3):
        for j in range(2):
            c = (px + (i - 1) * 0.32 * pk, 0.2 - 0.73 * pk, pz + (j - 0.5) * 0.36 * pk)
            tor.cyl(0.13 * pk, 0.1, c, "Y", "FRAME", seg=12)
            tor.cyl(0.09 * pk, 0.12, (c[0], c[1] - 0.01, c[2]), "Y", "DARK", seg=12)
    tor.box((0.5, 0.6, 0.35), (px + 0.2, 0.3, pz - 0.6 * pk), "FRAME")

    # arms
    for s, tag in ((1, "L"), (-1, "R")):
        x = s * 2.3 * B
        sh = P["shoulder_" + tag] = Part("shoulder_" + tag, (x, 0, 7.8), tor)
        sh.cyl(0.45, 0.55, (x - s * 0.05, 0, 7.8), "X", "FRAME", seg=20)
        sh.box((0.98 * B, 1.35, 1.0), (x + s * 0.18, 0, 8.02), "ARMOR")
        sh.bolts((x + s * 0.18, -0.66, 8.02), 0.98 * B, 1.0)
        sh.box((0.56, 0.62, 1.4), (x + s * 0.1, 0, 6.9), "FRAME", taper=0.0)
        sh.box((0.16, 0.72, 1.1), (x + s * 0.42, 0, 7.0), "ARMOR_ALT")
        ex = x + s * 0.1
        el = P["elbow_" + tag] = Part("elbow_" + tag, (ex, 0, 6.15), sh)
        el.cyl(0.33, 0.62, (ex, 0, 6.15), "X", "FRAME", seg=16)
        if tag == "R":  # rotary cannon
            el.box((0.78 * B, 1.5, 0.78 * B), (ex, -0.5, 6.0), "ARMOR")
            el.bolts((ex - 0.4 * B, -0.5, 6.0), 1.5, 0.78 * B, "-X")
            el.box((0.42, 0.7, 0.55), (ex - 0.55 * B, -0.2, 5.95), "ARMOR_ALT")
            el.cyl(0.46, 0.4, (ex, -1.35, 6.0), "Y", "FRAME", seg=20)
            el.box((0.06, 0.9, 0.2), (ex + 0.4 * B, -0.5, 6.1), "TRIM", bevel=0.01)
            g = P["gatling_spin"] = Part("gatling_spin", (ex, -1.55, 6.0), el)
            for k in range(6):
                a = k * math.pi / 3
                g.cyl(0.075, 1.9, (ex + 0.24 * math.cos(a), -2.45, 6.0 + 0.24 * math.sin(a)),
                      "Y", "BARREL", seg=10)
            g.cyl(0.1, 1.9, (ex, -2.45, 6.0), "Y", "DARK", seg=10)
            for yy in (-1.9, -3.2):
                g.cyl(0.38, 0.14, (ex, yy, 6.0), "Y", "FRAME", seg=18)
        else:  # laser forearm
            el.box((0.7 * B, 1.35, 0.72 * B), (ex, -0.45, 6.0), "ARMOR")
            el.bolts((ex + 0.36 * B, -0.45, 6.0), 1.35, 0.72 * B, "+X")
            el.box((0.5, 0.55, 0.55), (ex, -1.35, 5.95), "FRAME", taper=0.0)
            el.cyl(0.15, 0.9, (ex, -1.95, 5.98), "Y", "BARREL", seg=12)
            el.cyl(0.2, 0.12, (ex, -2.4, 5.98), "Y", "FRAME", seg=12)
            el.cyl(0.1, 0.13, (ex, -2.42, 5.98), "Y", "LAMP", seg=12)
            el.box((0.72 * B, 0.06, 0.14), (ex, -1.13, 6.3), "TRIM", bevel=0.01)

    cam = P["cockpit_cam"] = Part("cockpit_cam", (0, -1.25, 7.58), tor)

    order = ["root", "pelvis", "torso", "hip_L", "hip_R", "knee_L", "knee_R",
             "ankle_L", "ankle_R", "shoulder_L", "shoulder_R", "elbow_L", "elbow_R",
             "gatling_spin", "cockpit_cam"]
    for n in order:
        P[n].build(coll)

    decal(coll, "DECAL_27_chest", tor, (0.62, -0.935, 7.6), (1, 0, 0), (0, 0, 1), 0.55, 0.42)
    decal(coll, "DECAL_27_pod", tor, (px - 0.585 * pk - 0.01, 0.2, pz), (0, -1, 0), (0, 0, 1),
          0.6, 0.45)
    decal(coll, "DECAL_mark_L", P["shoulder_L"], (2.3 * B + 0.18 + 0.49 * B + 0.01, 0, 8.02),
          (0, 1, 0), (0, 0, 1), 0.5, 0.5)
    return P


# ---------------------------------------------------------------- cockpit
def build_cockpit():
    coll = bpy.context.scene.collection
    c = Part("cockpit", (0, 0, 0), slots=CP_MATS)
    win = {  # window: half-width, bottom z, top z, mullion x positions
        "A": dict(hw=0.95, bot=-0.2, top=0.24, mull=[-0.34, 0.34], depth=-1.05),
        "B": dict(hw=1.15, bot=-0.34, top=0.62, mull=[0.0], depth=-1.2),
        "C": dict(hw=1.0, bot=-0.2, top=0.3, mull=[0.0], depth=-1.0),
    }[VAR]
    hw, bot, top, d = win["hw"], win["bot"], win["top"], win["depth"]
    W = hw + 0.35
    # front wall around window
    c.box((2 * W, 0.12, 1.0), (0, d, bot - 0.5), "CP_FRAME", bevel=0.03)
    c.box((2 * W, 0.12, 0.8), (0, d, top + 0.4), "CP_FRAME", bevel=0.03)
    for sx in (-1, 1):
        c.box((0.35, 0.12, top - bot + 0.1), (sx * (hw + 0.17), d, (top + bot) / 2), "CP_FRAME",
              bevel=0.03)
    for mx in win["mull"]:
        c.box((0.07 if VAR == "B" else 0.1, 0.16, top - bot + 0.05), (mx, d + 0.03, (top + bot) / 2),
              "CP_FRAME", bevel=0.02)
    if VAR == "C":  # chamfered corners
        for sx in (-1, 1):
            for sz, zz in ((1, top), (-1, bot)):
                c.box((0.3, 0.14, 0.3), (sx * (hw - 0.02), d + 0.01, zz - sz * 0.02), "CP_FRAME",
                      bevel=0.0, rot=("Y", math.pi / 4))
    if VAR == "B":  # wraparound side glass + canopy ribs
        for sx in (-1, 1):
            c.box((0.06, 0.9, 0.06), (sx * (hw + 0.02), d + 0.45, top), "CP_FRAME", bevel=0.01)
            c.box((0.06, 0.06, 0.95), (sx * (hw + 0.32), d + 0.75, (top + bot) / 2), "CP_FRAME",
                  bevel=0.01)
    # glass pane (tinted in runtime)
    g = bmesh.new()
    bmesh.ops.create_grid(g, x_segments=1, y_segments=1, size=0.5)
    for v in g.verts:
        v.co.x *= 2 * hw * 1.02; v.co.y *= (top - bot) * 1.05
    bmesh.ops.rotate(g, verts=g.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(g, verts=g.verts, vec=Vector((0, d - 0.02, (top + bot) / 2)))
    c._merge(g, "GLASS", False)
    # walls, ceiling, floor
    for sx in (-1, 1):
        c.box((0.12, 2.2, 2.0), (sx * (W + 0.05), 0.0, 0.0), "CP_PANEL", bevel=0.03)
    c.box((2 * W + 0.2, 2.4, 0.12), (0, 0.1, top + 0.72), "CP_PANEL", bevel=0.03)
    c.box((2 * W + 0.2, 2.4, 0.12), (0, 0.1, -1.05), "CP_FRAME", bevel=0.03)
    # dashboard: base + angled top carrying three screens
    c.box((2 * W - 0.1, 0.55, 0.62), (0, d + 0.3, bot - 0.56), "CP_PANEL", bevel=0.04)
    tilt = math.radians(-38)
    c.box((2 * W - 0.2, 0.62, 0.08), (0, d + 0.25, bot - 0.22), "CP_FRAME", bevel=0.02,
          rot=("X", tilt))
    c.box((2 * W - 0.1, 0.05, 0.04), (0, d + 0.5, bot - 0.44), "CP_TRIM", bevel=0.0)
    sw = [(0.62, "SCREEN_L", 0.42), (0.0, "SCREEN_C", 0.52), (-0.62, "SCREEN_R", 0.42)]  # +X is the pilot's left
    n = Matrix.Rotation(tilt, 3, "X") @ Vector((0, 0, 1))
    up = -(Matrix.Rotation(tilt, 3, "X") @ Vector((0, 1, 0)))
    screens = []
    for sx, name, w in sw:
        base = Vector((sx, d + 0.25, bot - 0.22))
        c.box((w + 0.06, 0.4, 0.03), base + n * 0.045, "DARK", bevel=0.0, rot=("X", tilt))
        screens.append((name, base + n * 0.064, w))
    # side consoles with button banks
    for sx in (-1, 1):
        cx = sx * (W - 0.28)
        c.box((0.48, 1.1, 0.5), (cx, -0.15, -0.72), "CP_PANEL", bevel=0.04)
        c.box((0.44, 1.0, 0.04), (cx, -0.15, -0.46), "CP_FRAME", bevel=0.0)
        for i in range(4):
            for j in range(3):
                mat = "LAMP" if (i + j + (sx > 0)) % 3 == 0 else "DARK"
                c.box((0.07, 0.07, 0.04), (cx - 0.12 + j * 0.12, -0.5 + i * 0.16, -0.43), mat,
                      bevel=0.008, seg=1)
        c.box((0.3, 0.05, 0.9), (sx * (W - 0.02), -0.5, 0.05), "CP_TRIM", bevel=0.01)
        for k in range(3):  # conduit runs on walls
            c.cyl(0.035, 2.0, (sx * (W - 0.05), 0.0, 0.3 + k * 0.09), "Y", "BARREL", seg=8)
    # throttle (left) and stick (right)
    c.box((0.12, 0.35, 0.08), (-0.55, 0.05, -0.62), "CP_FRAME", bevel=0.02)
    c.cyl(0.025, 0.35, (-0.55, 0.02, -0.45), "Z", "BARREL", seg=8)
    c.box((0.1, 0.08, 0.14), (-0.55, 0.02, -0.26), "CP_TRIM", bevel=0.02)
    c.cyl(0.03, 0.4, (0.5, 0.05, -0.62), "Z", "BARREL", seg=8)
    c.box((0.08, 0.1, 0.2), (0.5, 0.05, -0.36), "DARK", bevel=0.03)
    c.box((0.03, 0.03, 0.03), (0.5, 0.0, -0.25), "LAMP", bevel=0.005, seg=1)
    # overhead panel + grab bar
    c.box((1.0, 0.7, 0.14), (0, -0.3, top + 0.6), "CP_FRAME", bevel=0.03)
    for i in range(6):
        c.box((0.04, 0.04, 0.05), (-0.3 + i * 0.12, -0.52, top + 0.51),
              "LAMP" if i in (1, 4) else "DARK", bevel=0.005, seg=1)
    c.cyl(0.03, 1.4, (0, d + 0.25, top + 0.5), "X", "BARREL", seg=8)
    # warning strip over window
    c.build(coll)
    for name, ctr, w in screens:  # separate objects so their UVs survive
        decal(coll, name, c, ctr, (-1, 0, 0), up, w, 0.34, mat=name)


# ---------------------------------------------------------------- output
def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_yup=True, export_materials="EXPORT",
                              export_extras=False, export_cameras=False, export_lights=False)


def render_hero(path):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    try:
        sc.cycles.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1200, 1500
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("W"); sc.world = world
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*hex2rgb("#b9b3a6"), 1)
    bg.inputs[1].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=80)
    fl = bpy.context.active_object
    fl.data.materials.append(make_mat("FLOOR", "#8d8a83", 0.0, 0.55))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(4)
    sun.rotation_euler = (math.radians(52), math.radians(8), math.radians(-35))
    sc.collection.objects.link(sun)
    rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "AREA"))
    rim.data.energy = 4000; rim.data.size = 8
    rim.location = (-6, 9, 12)
    rim.rotation_euler = Vector((6, -9, -8)).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(rim)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 55
    cam.location = (-9.5, -17.5, 4.2)
    cam.rotation_euler = (Vector((0, 0, 5.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(cam)
    sc.camera = cam
    # stance pose for the still
    ob = bpy.data.objects
    for tag, s in (("L", 1), ("R", -1)):
        ob["hip_" + tag].rotation_euler.x = math.radians(14 if tag == "L" else -8)
        ob["knee_" + tag].rotation_euler.x = math.radians(-26 if tag == "L" else -14)
        ob["ankle_" + tag].rotation_euler.x = math.radians(12 if tag == "L" else 22)
    ob["pelvis"].location.z = 5.05
    ob["torso"].rotation_euler.z = math.radians(-10)
    ob["shoulder_R"].rotation_euler.x = math.radians(8)
    ob["elbow_L"].rotation_euler.x = math.radians(-10)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    reset(); build_mats(); build_striker()
    export(os.path.join(OUT, f"striker_{VAR}.glb"))
    if RENDER:
        render_hero(os.path.join(OUT, f"striker_{VAR}.png"))
    reset(); build_mats(); build_cockpit()
    export(os.path.join(OUT, f"cockpit_{VAR}.glb"))
    print("IRONWAKE_DONE", VAR)

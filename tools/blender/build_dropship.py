"""IRON WAKE - LANTERN-class dropship generator + mission intro film.

Usage:
  blender -b -P tools/blender/build_dropship.py -- <out_dir>                  # GLB only
  blender -b -P tools/blender/build_dropship.py -- <out_dir> --film <frames>  # + PNG frames

Conventions match build_striker.py: Z up, ship faces -Y, 1 unit = 1 m.
Pivots: ship (root), engine_FL/FR/RL/RR (tilt about X), clamp, mech_mount
(where the carried mech's root sits; the mech's feet hang 13.4 m below the hull).
"""
import bpy, bmesh, math, sys, os, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "."
FILM = argv[argv.index("--film") + 1] if "--film" in argv else None
HERE = os.path.dirname(os.path.abspath(__file__))
PAL = json.load(open(os.path.join(HERE, "palettes.json")))["C"]
MATS = ["ARMOR", "ARMOR_ALT", "FRAME", "TRIM", "GLASS", "LAMP", "THRUST", "DARK", "BARREL"]


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name, col, metal=0.2, rough=0.6, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*lin(col), 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(col), 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def camo(m, cols, cell=0.3):
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sn = nt.nodes.new("ShaderNodeVectorMath"); sn.operation = "SNAP"; sn.inputs[1].default_value = (cell,) * 3
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.5
    rp = nt.nodes.new("ShaderNodeValToRGB"); rp.color_ramp.interpolation = "CONSTANT"
    e = rp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (*lin(cols[0]), 1)
    e[1].position, e[1].color = 0.47, (*lin(cols[1]), 1)
    e.new(0.58).color = (*lin(cols[2]), 1)
    nt.links.new(tc.outputs["Object"], sn.inputs[0]); nt.links.new(sn.outputs[0], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], rp.inputs["Fac"]); nt.links.new(rp.outputs["Color"], b.inputs["Base Color"])


def build_mats():
    p = PAL
    mat("ARMOR", p["camo"][0], 0.15, 0.62); mat("ARMOR_ALT", p["armor_alt"], 0.2, 0.55)
    mat("FRAME", p["frame"], 0.7, 0.45); mat("TRIM", p["trim"], 0.1, 0.5)
    mat("GLASS", "#ff3a2a", 0.0, 0.1, emit=1.2); mat("LAMP", p["lamp"], 0, 0.3, emit=8)
    mat("THRUST", "#ffb070", 0, 0.2, emit=14); mat("DARK", p["dark"], 0.3, 0.85)
    mat("BARREL", p["barrel"], 0.9, 0.3)
    camo(bpy.data.materials["ARMOR"], p["camo"])


class Part:
    def __init__(self, name, world, parent=None):
        self.name, self.world, self.parent = name, Vector(world), parent
        self.bm = bmesh.new(); self.obj = None

    def _merge(self, tmp, m, smooth=False):
        for f in tmp.faces:
            f.material_index = MATS.index(m); f.smooth = smooth
        bmesh.ops.translate(tmp, verts=tmp.verts, vec=-self.world)
        me = bpy.data.meshes.new("_t"); tmp.to_mesh(me); tmp.free()
        self.bm.from_mesh(me); bpy.data.meshes.remove(me)

    def box(self, size, c, m="ARMOR", bevel=0.06, taper=0.0, rot=None, taper_y=0.0):
        t = bmesh.new(); bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
            if taper and v.co.z > 0:
                v.co.x *= 1 - taper
            if taper_y and v.co.y < 0:  # narrows toward the nose
                v.co.x *= 1 - taper_y; v.co.z *= 1 - taper_y * 0.6
        if bevel:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=min(bevel, min(size) * 0.3), segments=1,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
        if rot:
            bmesh.ops.rotate(t, verts=t.verts, matrix=Matrix.Rotation(rot[1], 3, rot[0]))
        bmesh.ops.translate(t, verts=t.verts, vec=Vector(c))
        self._merge(t, m)

    def cyl(self, r, d, c, axis="Z", m="FRAME", seg=20, r2=None):
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                              radius2=r if r2 is None else r2, depth=d)
        if axis == "X":
            bmesh.ops.rotate(t, verts=t.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
        elif axis == "Y":
            bmesh.ops.rotate(t, verts=t.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.translate(t, verts=t.verts, vec=Vector(c))
        self._merge(t, m, smooth=True)

    def build(self, coll):
        me = bpy.data.meshes.new(self.name + "_mesh"); self.bm.to_mesh(me); self.bm.free()
        for s in MATS:
            me.materials.append(bpy.data.materials[s])
        piv = bpy.data.objects.new(self.name, None); coll.objects.link(piv)
        if self.parent:
            piv.parent = self.parent.obj; piv.location = self.world - self.parent.world
        else:
            piv.location = self.world
        ob = bpy.data.objects.new(self.name + "_mesh", me); coll.objects.link(ob); ob.parent = piv
        for poly in me.polygons:
            pass
        self.obj = piv
        return piv


def build_ship():
    coll = bpy.context.scene.collection
    ship = Part("ship", (0, 0, 0))
    # hull, nose, spine, belly
    ship.box((6.6, 20, 3.6), (0, 1, 0), "ARMOR", bevel=0.25, taper=0.12)
    ship.box((6.0, 6.5, 3.2), (0, -12, -0.1), "ARMOR_ALT", bevel=0.25, taper_y=0.45, taper=0.1)
    ship.box((3.4, 1.2, 0.55), (0, -14.2, 0.85), "GLASS", bevel=0.05, rot=("X", 0.45))
    ship.box((3.0, 15, 1.3), (0, 2, 2.3), "FRAME", bevel=0.15, taper=0.25)
    ship.box((4.2, 12, 0.5), (0, 1, -1.95), "DARK", bevel=0.05)
    for i in range(5):
        ship.box((2.6, 0.12, 0.8), (0, 4 + i * 1.3, 3.0), "DARK", bevel=0.0)
    for sx in (-1, 1):
        ship.box((0.1, 14, 0.35), (sx * 3.32, 1, 0.6), "TRIM", bevel=0.0)
        ship.box((0.25, 0.25, 0.25), (sx * 3.4, -9, 0.2), "LAMP", bevel=0.02)
        # stub wings front and rear
        for wy in (-5.5, 7.5):
            ship.box((5.2, 3.4, 0.9), (sx * 5.6, wy, 0.4), "FRAME", bevel=0.12, taper=0.1)
    # tail boom + fins
    ship.box((2.4, 8, 1.8), (0, 14.5, 0.9), "ARMOR", bevel=0.15, taper=0.2)
    for sx in (-1, 1):
        ship.box((0.35, 3.2, 3.8), (sx * 1.6, 17.2, 3.0), "ARMOR_ALT", bevel=0.08,
                 rot=("Y", sx * 0.35))
        ship.box((0.2, 0.2, 0.2), (sx * 2.4, 17.6, 4.7), "LAMP", bevel=0.02)
    ship.cyl(0.9, 1.2, (0, 18.8, 0.9), "Y", "DARK", seg=16)
    ship.cyl(0.6, 0.3, (0, 19.4, 0.9), "Y", "THRUST", seg=16)
    # engines (tilting nacelles)
    engines = []
    for tag, sx, wy in (("FL", -1, -5.5), ("FR", 1, -5.5), ("RL", -1, 7.5), ("RR", 1, 7.5)):
        e = Part("engine_" + tag, (sx * 9.4, wy, 0.4), ship)
        x = sx * 9.4
        e.cyl(1.75, 4.6, (x, wy, 0.4), "Z", "ARMOR", seg=24)
        e.cyl(1.9, 0.5, (x, wy, 2.6), "Z", "FRAME", seg=24)
        e.cyl(1.9, 0.5, (x, wy, -1.8), "Z", "FRAME", seg=24)
        e.cyl(1.35, 0.3, (x, wy, -2.1), "Z", "DARK", seg=24)
        e.cyl(1.1, 0.2, (x, wy, -2.2), "Z", "THRUST", seg=24)
        e.box((0.08, 2.2, 1.2), (x + sx * 1.78, wy, 0.4), "TRIM", bevel=0.0)
        engines.append(e)
    clamp = Part("clamp", (0, 0.5, -2.2), ship)
    for cx in (-1.6, 1.6):
        for cy in (-1.6, 2.6):
            clamp.box((0.5, 0.7, 2.2), (cx, 0.5 + cy, -3.1), "FRAME", bevel=0.05)
            clamp.box((0.8, 0.9, 0.35), (cx, 0.5 + cy, -4.1), "DARK", bevel=0.05)
    mount = Part("mech_mount", (0, 0.5, -13.6), ship)
    for p in [ship] + engines + [clamp, mount]:
        p.build(coll)
    return bpy.data.objects["ship"]


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False)


# ---------------------------------------------------------------- film
def key(ob, f, loc=None, rot=None):
    if loc is not None:
        ob.location = loc; ob.keyframe_insert("location", frame=f)
    if rot is not None:
        ob.rotation_euler = rot; ob.keyframe_insert("rotation_euler", frame=f)


def film(frames_dir):
    sc = bpy.context.scene
    ship = bpy.data.objects["ship"]
    # carried mech
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "../../assets/mechs/striker_C.glb"))
    mroot = bpy.data.objects["root"]
    mroot.parent = bpy.data.objects["mech_mount"]; mroot.location = (0, 0, 0)
    mroot.rotation_mode = "XYZ"
    for n, v in (("hip_L", 0.18), ("hip_R", 0.1), ("knee_L", -0.25), ("knee_R", -0.2),
                 ("ankle_L", 0.2), ("ankle_R", 0.25)):
        if n in bpy.data.objects:
            bpy.data.objects[n].rotation_euler.x = v
    if "ARMOR" in bpy.data.materials:
        for m in bpy.data.materials:
            if m.name.startswith("ARMOR") and m.name != "ARMOR_ALT" and m.node_tree:
                if not any(n.type == "TEX_NOISE" for n in m.node_tree.nodes):
                    camo(m, PAL["camo"], 0.22)
    # terrain
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=400, y_subdivisions=400, size=2400)
    ter = bpy.context.active_object
    tex = bpy.data.textures.new("dunes", "CLOUDS"); tex.noise_scale = 90; tex.noise_depth = 3
    md = ter.modifiers.new("disp", "DISPLACE"); md.texture = tex; md.strength = 26; md.mid_level = 0.5
    tex2 = bpy.data.textures.new("ripples", "CLOUDS"); tex2.noise_scale = 12
    md2 = ter.modifiers.new("disp2", "DISPLACE"); md2.texture = tex2; md2.strength = 2.5
    bpy.ops.object.shade_smooth()
    tm = bpy.data.materials.new("TERRAIN")
    if tm.node_tree is None:
        tm.use_nodes = True
    nt = tm.node_tree; b = nt.nodes["Principled BSDF"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.08
    mx = nt.nodes.new("ShaderNodeMath"); mx.operation = "MULTIPLY_ADD"
    mx.inputs[1].default_value = 1.0; nt.links.new(sep.outputs["Z"], mx.inputs[0])
    nt.links.new(nz.outputs["Fac"], mx.inputs[2])
    rp = nt.nodes.new("ShaderNodeValToRGB"); e = rp.color_ramp.elements
    e[0].position, e[0].color = 1.25, (*lin("#4e443c"), 1)
    e[1].position, e[1].color = 1.42, (*lin("#b08a66"), 1)
    mr = nt.nodes.new("ShaderNodeMapRange"); mr.inputs[1].default_value = 1.0; mr.inputs[2].default_value = 2.0
    nt.links.new(mx.outputs[0], mr.inputs[0]); nt.links.new(mr.outputs[0], rp.inputs[0])
    nt.links.new(rp.outputs[0], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.95
    ter.data.materials.append(tm)
    import random
    random.seed(7)
    rock = mat("ROCK", "#5a4a40", 0, 0.95)
    for i in range(22):
        a = random.uniform(0, 6.28); r = random.uniform(160, 900)
        h = random.uniform(40, 150); rad = random.uniform(25, 70)
        bpy.ops.mesh.primitive_cylinder_add(vertices=7, radius=rad, depth=h,
                                            location=(math.cos(a) * r, math.sin(a) * r - 200, h / 2 - 8))
        o = bpy.context.active_object; o.data.materials.append(rock)
        for v in o.data.vertices:
            if v.co.z > 0:
                v.co.x *= 0.7; v.co.y *= 0.7
    # dusk
    world = bpy.data.worlds.new("W"); sc.world = world
    if world.node_tree is None:
        world.use_nodes = True
    wn = world.node_tree
    sky = wn.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "NISHITA"
    except Exception:
        pass
    for attr, val in (("sun_elevation", math.radians(2.5)), ("sun_rotation", math.radians(200)),
                      ("air_density", 1.6), ("dust_density", 4.0)):
        if hasattr(sky, attr):
            setattr(sky, attr, val)
    wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs[0])
    wn.nodes["Background"].inputs[1].default_value = 0.22
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0; sun.data.color = lin("#ffb07a"); sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(84), 0, math.radians(200 - 90)); sc.collection.objects.link(sun)
    sc.render.use_motion_blur = True

    # animation: 24 fps, 216 frames
    sc.render.fps = 24; sc.frame_start, sc.frame_end = 1, 216
    ship.rotation_mode = "XYZ"
    key(ship, 1, (26, 330, 62), (0.04, -0.12, 0.12))
    key(ship, 80, (4, 40, 36), (0.06, -0.2, 0.05))
    key(ship, 130, (0, -40, 26), (-0.16, 0.0, 0.0))
    key(ship, 216, (0, -78, 21), (-0.03, 0.0, 0.0))
    for n in ("engine_FL", "engine_FR", "engine_RL", "engine_RR"):
        e = bpy.data.objects[n]; e.rotation_mode = "XYZ"
        key(e, 1, rot=(0.95, 0, 0)); key(e, 70, rot=(0.9, 0, 0)); key(e, 150, rot=(-0.05, 0, 0))
        key(e, 216, rot=(0.0, 0, 0))
    tgt = bpy.data.objects.new("aim", None); sc.collection.objects.link(tgt)
    tgt.parent = ship; tgt.location = (0, 0, -5)

    def camera(name, keys, lens):
        c = bpy.data.objects.new(name, bpy.data.cameras.new(name)); sc.collection.objects.link(c)
        c.data.lens = lens
        for f, loc in keys:
            key(c, f, loc)
        con = c.constraints.new("TRACK_TO"); con.target = tgt
        con.track_axis = "TRACK_NEGATIVE_Z"; con.up_axis = "UP_Y"
        return c
    c1 = camera("cam_ground", [(1, (16, -22, 5)), (100, (13, -26, 4))], 24)
    c2 = camera("cam_chase", [(101, (-58, 6, 34)), (216, (-50, -118, 15))], 34)
    m1 = sc.timeline_markers.new("c1", frame=1); m1.camera = c1
    m2 = sc.timeline_markers.new("c2", frame=101); m2.camera = c2
    sc.camera = c1

    for o in bpy.data.objects:
        if o.animation_data and o.animation_data.action:
            try:
                for fc in o.animation_data.action.fcurves:
                    for kp in fc.keyframe_points:
                        kp.interpolation = "BEZIER"
            except AttributeError:
                pass

    sc.render.engine = "BLENDER_EEVEE"
    try:
        sc.eevee.taa_render_samples = 24
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = os.path.join(frames_dir, "f_")
    only = [a for a in argv if a.startswith("--only=")]
    if only:
        f = int(only[0].split("=")[1]); sc.frame_start = sc.frame_end = f
    bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_mats(); build_ship()
    os.makedirs(OUT, exist_ok=True)
    export(os.path.join(OUT, "dropship.glb"))
    if FILM:
        os.makedirs(FILM, exist_ok=True)
        film(FILM)
    print("IRONWAKE_DONE dropship")

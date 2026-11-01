"""Build Silicium's inspectable hardware model. Blender 5.x, no external assets.

blender -b -P tools/blender/build_model.py -- App/Resources/Silicium.usdz
Optional: --render build/visual-review/studio.png

Inspired by teardown photography, not a dimensional replica of an Apple board.
PART__ names are the interaction contract. LAYER__silicon is a schematic overlay.
All texture maps are authored here and embedded in USDZ. Decorative meshes are
batched by material and layer to keep the live monitor inexpensive to render.
"""
import bpy
import math
import random
import sys
from pathlib import Path
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = str(Path(args[0] if args else '/tmp/Silicium.usdz').resolve())
RENDER = args[args.index('--render') + 1] if '--render' in args else None
random.seed(17)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
texture_dir = Path(OUT).parent / '.silicium-textures'
texture_dir.mkdir(parents=True, exist_ok=True)


def surface_map(name, roughness, grain, brushed=False):
    """Portable image roughness; no runtime dependency on Blender shader nodes."""
    n = 512
    rng = np.random.default_rng(42)
    noise = rng.normal(0, grain, (n, n))
    if brushed:
        noise += rng.normal(0, grain * .5, (n, 1))
    values = np.clip(roughness + noise, 0.05, 0.95)
    rgba = np.ones((n, n, 4), dtype=np.float32)
    rgba[:, :, :3] = values[:, :, None]
    image = bpy.data.images.new(name, width=n, height=n, alpha=False)
    image.colorspace_settings.name = 'Non-Color'
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(texture_dir / (name + '.png'))
    image.file_format = 'PNG'
    image.save()
    return image


def material(name, color, rough=0.5, metal=0, grain=0, brushed=False):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    if grain:
        tex = m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = surface_map(name + '_roughness', rough, grain, brushed)
        m.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Roughness'])
    return m


M = {
    'pcb': material('Solder mask • charcoal', (.023, .029, .025), .64, .1, .025),
    'edge': material('FR4 • cut edge', (.12, .105, .055), .8),
    'substrate': material('Package substrate', (.024, .075, .05), .5, .15),
    'alu': material('Bead blasted aluminium', (.49, .52, .55), .32, .94, .04, True),
    'shield': material('Nickel shield', (.39, .41, .43), .25, .95, .035, True),
    'solder': material('Tin solder', (.51, .53, .55), .23, 1),
    'gold': material('Contact gold', (.64, .43, .13), .28, .85),
    'copper': material('Copper flex', (.24, .105, .035), .38, .65),
    'black': material('Moulded polymer', (.014, .016, .019), .69, 0, .035),
    'package': material('Epoxy packages', (.031, .034, .039), .52, .05, .04),
    'battery': material('Graphite pouch', (.022, .024, .028), .48, .25, .035, True),
    'seam': material('Pouch seal', (.038, .041, .045), .36, .45),
    'silicon': material('Polished silicon', (.055, .07, .10), .16, .72, .008),
    'ceramic': material('Ceramic capacitors', (.23, .18, .12), .55),
    'ink': material('Laser marking', (.43, .45, .44), .85),
    'white': material('PCB silkscreen', (.64, .66, .60), .9),
    'core': material('Schematic silicon', (.075, .14, .19), .34, .35),
}


def empty(name, parent=None, loc=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    return o


def P(x, z, y=0):
    return (x, -z, y)  # Application: X right, Y up, Z towards viewer.


mesh_cache = {}


def box(name, size, loc, mat, parent, bevel=.001):
    key = ('box', size, bevel, mat.name)
    if key in mesh_cache:
        o = bpy.data.objects.new(name, mesh_cache[key])
        bpy.context.collection.objects.link(o)
        o.parent = parent
        o.location = loc
        return o
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Machined edge', 'BEVEL')
        mod.width = min(bevel, min(size) * .43)
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod = o.modifiers.new('Face normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    o.parent = parent
    o.location = loc
    mesh_cache[key] = o.data
    return o


def cylinder(name, radius, depth, loc, mat, parent, vertices=24):
    key = ('cylinder', radius, depth, vertices, mat.name)
    if key in mesh_cache:
        o = bpy.data.objects.new(name, mesh_cache[key])
        bpy.context.collection.objects.link(o)
        o.parent = parent
        o.location = loc
        return o
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    o.parent = parent
    o.location = loc
    bevel = o.modifiers.new('Rim', 'BEVEL')
    bevel.width = min(.0006, depth * .2)
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    mesh_cache[key] = o.data
    return o


def trace(name, points, radius, mat, parent):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    o = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(o)
    o.parent = parent
    o.data.materials.append(mat)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target='MESH')
    o.select_set(False)
    return o


def text(label, x, z, y, size, parent, mat=None):
    curve = bpy.data.curves.new('Etching', 'FONT')
    curve.body = label
    curve.size = size
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.extrude = 0
    curve.resolution_u = 2
    o = bpy.data.objects.new('DETAIL__marking', curve)
    bpy.context.collection.objects.link(o)
    o.parent = parent
    o.location = P(x, z, y)
    o.data.materials.append(mat or M['ink'])
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')
    o.select_set(False)


def screw(x, z, y, parent, radius=.006):
    cylinder('DETAIL__screw_seat', radius * 1.5, .001, P(x, z, y), M['shield'], parent)
    cylinder('DETAIL__screw_head', radius, .002, P(x, z, y + .001), M['solder'], parent)
    # Six-lobed recess, dark geometry inset into the head.
    for a in range(3):
        o = box('DETAIL__screw_recess', (radius * 1.15, radius * .22, .0002), P(x, z, y + .0021), M['black'], parent, .0001)
        o.rotation_euler.z = a * math.pi / 3


root = empty('SILICIUM_ROOT')
board = empty('LAYER__board', root)
battery = empty('LAYER__battery', root)
chassis = empty('LAYER__chassis', root)
lid = empty('LAYER__lid', board)
silicon = empty('LAYER__silicon', board)

# Unibody tray, stepped inner lip, screw bosses and speaker enclosures.
box('DETAIL__tray', (1.12, .94, .018), P(0, .12, -.035), M['alu'], chassis, .018)
box('DETAIL__tray_liner', (1.075, .895, .002), P(0, .12, -.025), M['black'], chassis, .018)
for x in [-.547, .547]:
    spans = [(-.327, .567)] if x > 0 else [(-.327, -.276), (-.204, -.159), (-.101, -.066), (-.014, .567)]
    for start, end in spans:
        box('DETAIL__sidewall', (.016, end - start, .030), P(x, (start + end) / 2, -.014), M['alu'], chassis, .006)
for z in [-.337, .577]:
    box('DETAIL__endwall', (1.08, .018, .030), P(0, z, -.014), M['alu'], chassis, .006)
for x in [-.526, .526]:
    for z in [-.31, .16, .55]:
        screw(x, z, -.001, chassis)
for x in [-.485, .485]:
    box('DETAIL__speaker', (.075, .355, .030), P(x, .355, -.007), M['black'], chassis, .015)
    for z in [.23, .46]:
        box('DETAIL__speaker_grille', (.044, .085, .001), P(x, z, .009), M['package'], chassis, .012)
        for i in range(12):
            box('DETAIL__speaker_slot', (.031, .0017, .0005), P(x, z - .031 + i * .0056, .010), M['black'], chassis, .0007)

# PCB outline with a stepped shoulder, exposed laminate and grounded shield rails.
outline = [(-.49, -.30), (-.34, -.30), (-.34, -.32), (-.07, -.32), (-.07, -.275),
           (.11, -.275), (.13, -.245), (.46, -.245), (.49, -.22), (.49, .13),
           (.44, .16), (.09, .16), (.06, .13), (-.46, .13), (-.49, .10)]
def pcb_polygon(name, y, material):
    vertices = [P(x, z, y) for x, z in outline]
    mesh = bpy.data.meshes.new(name)
    # P flips depth, so reverse winding to keep the solder-mask face pointing up.
    mesh.from_pydata(vertices, [], [list(reversed(range(len(vertices))))])
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.parent = board
    o.data.materials.append(material)
    mod = o.modifiers.new('Board thickness', 'SOLIDIFY')
    mod.thickness = .006
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
pcb_polygon('DETAIL__laminate', -.004, M['edge'])
pcb_polygon('PART__board__pcb', .001, M['pcb'])
for pts in [[(-.46, .10), (-.46, -.26), (-.32, -.26), (-.32, -.285), (-.085, -.285), (-.085, -.24), (.07, -.24), (.07, .10), (-.46, .10)],
            [(.12, .125), (.46, .125), (.46, -.20), (.15, -.20), (.12, -.16), (.12, .125)]]:
    trace('DETAIL__shield_rail', [P(x, z, .006) for x, z in pts], .0025, M['shield'], board)
for x, z in [(-.46, -.25), (-.46, .09), (-.07, .09), (.10, -.21), (.46, .11), (.46, -.19)]:
    cylinder('DETAIL__ground_pad', .010, .0005, P(x, z, .002), M['gold'], board)
    screw(x, z, .003, board, .0045)

print('Main package:', flush=True)
# Main package: unified memory sits alongside the die on its green substrate.
box('PART__chip__substrate', (.245, .25, .007), P(-.17, -.10, .007), M['substrate'], board, .002)
for i, x in enumerate([-.228, -.112]):
    box(f'PART__memory__package{i}', (.106, .057, .009), P(x, -.182, .015), M['package'], board, .002)
    text('UNIFIED MEMORY', x, -.185, .0196, .007, board)
    text('LPDDR  /  Si', x, -.171, .0196, .0055, board)
box('PART__chip__die', (.177, .151, .005), P(-.17, -.065, .014), M['silicon'], lid, .0015)
text('SILICON', -.17, -.078, .0167, .023, lid)
text('SYSTEM ON A CHIP', -.17, -.047, .0167, .0075, lid)
for x in [-.281, -.059]:
    for i in range(12):
        z = -.135 + i * .011
        box('DETAIL__package_cap', (.007, .004, .002), P(x, z, .012), M['ceramic'], board, .0004)
        for dx in [-.003, .003]:
            box('DETAIL__package_solder', (.0014, .004, .0022), P(x + dx, z, .012), M['solder'], board, .0003)

# Educational die; physical materials remain untouched when it is hidden.
box('DETAIL__schematic_base', (.177, .151, .004), P(-.17, -.065, .014), M['silicon'], silicon)
for comp, origin, count, columns, size in [
    ('performanceCores', (-.225, -.107), 4, 2, (.034, .032)),
    ('efficiencyCores', (-.235, -.036), 6, 3, (.022, .022)),
    ('gpu', (-.149, -.112), 8, 2, (.027, .023)),
    ('neuralEngine', (-.132, -.010), 1, 1, (.065, .022)),
]:
    for i in range(count):
        x = origin[0] + (i % columns) * (size[0] + .004)
        z = origin[1] + (i // columns) * (size[1] + .004)
        box(f'PART__{comp}__{i}', (*size, .002), P(x, z, .0175), M['core'], silicon, .0006)
        for j in range(5):
            box('DETAIL__die_cells', (size[0] * .8, .0005, .0002), P(x, z - size[1] * .33 + j * size[1] * .16, .0186), M['gold'], silicon, 0)

# NAND packages, with laser legends and tiny orientation dots.
for i, z in enumerate([-.17, -.035]):
    box(f'PART__ssd__nand{i}', (.106, .105, .010), P(-.374, z, .008), M['package'], board, .002)
    text('NAND', -.374, z - .011, .0132, .014, board)
    text('FLASH STORAGE', -.374, z + .013, .0132, .0057, board)
    cylinder('DETAIL__pin_one', .002, .0002, P(-.418, z + .043, .0133), M['ink'], board)

print('Power regulation,', flush=True)
# Power regulation, wireless can and dense, intentionally routed passive banks.
box('PART__wireless__module', (.136, .075, .012), P(.35, -.16, .010), M['shield'], board, .003)
text('WIRELESS', .35, -.16, .0162, .012, board)
for x in [.307, .39]:
    cylinder('DETAIL__antenna_socket', .004, .003, P(x, -.208, .005), M['gold'], board)
    trace('DETAIL__antenna_coax', [P(x, -.208, .007), P(x, -.28, .012), P(.48, -.29, .012)], .0013, M['black'], board)
for row in range(3):
    for col in range(2):
        x, z = .167 + col * .060, -.135 + row * .065
        box('DETAIL__inductor', (.050, .050, .017), P(x, z, .010), M['package'], board, .002)
        box('DETAIL__inductor_cap', (.047, .047, .001), P(x, z, .019), M['shield'], board, .002)
        text('R22', x, z, .0196, .012, board, M['black'])
for i, (x, z) in enumerate([(.035, -.15), (.035, -.045), (.35, -.035), (.35, .065), (-.20, .087)]):
    box('DETAIL__controller', (.06, .052, .006), P(x, z, .006), M['package'], board, .001)
    text('PMIC' if i < 4 else 'I/O', x, z, .0092, .008, board)
    for side in [-1, 1]:
        for j in range(10):
            box('DETAIL__controller_pin', (.003, .002, .001), P(x + side * .032, z - .021 + j * .0045, .004), M['solder'], board, .0003)

def passive(x, z, horizontal=False):
    w, d = (.007, .0035) if horizontal else (.0035, .007)
    box('DETAIL__passive', (w, d, .0028), P(x, z, .0035), M['ceramic'] if random.random() > .3 else M['package'], board, .0003)
    for sign in [-1, 1]:
        dx, dz = (sign * w * .39, 0) if horizontal else (0, sign * d * .39)
        box('DETAIL__solder', (.0015 if horizontal else w, d if horizontal else .0015, .003), P(x + dx, z + dz, .0035), M['solder'], board, .0004)

for x0, z0, cols, rows in [(-.427, -.265, 26, 3), (-.425, .046, 25, 3), (-.035, -.21, 8, 5),
                          (-.035, .016, 10, 7), (.285, -.105, 16, 3), (.285, .112, 16, 3),
                          (.27, -.08, 3, 16), (.425, -.102, 3, 18),
                          (-.311, -.214, 2, 23), (-.44, -.214, 2, 23),
                          (-.277, -.244, 21, 2), (-.035, -.116, 5, 9),
                          (.122, -.184, 14, 2), (.12, .043, 15, 7)]:
    for r in range(rows):
        for c in range(cols):
            passive(x0 + c * .008, z0 + r * .010, r % 3 == 0)

print('PCB buses', flush=True)
# PCB buses use orderly bends and vias, subtly visible through the solder mask.
for i in range(22):
    x = -.31 + i * .011
    trace('DETAIL__pcb_trace', [P(x, .037, .0015), P(x, .068, .0015), P(x + .016, .084, .0015)], .00035, M['substrate'], board)
    cylinder('DETAIL__via', .001, .0002, P(x + .016, .084, .0018), M['gold'], board, 12)
text('S I L I C I U M   /   L O G I C   B O A R D', -.20, -.305, .002, .0065, board, M['white'])

# Open port shells: separate walls, a recessed tongue, visible contacts.
for i, z in enumerate([-.24, -.13, -.04]):
    width = .060 if i == 0 else .047
    name = f'PART__power__port{i}'
    port = empty(name, board)
    for y in [.003, .021]:
        box('DETAIL__port_shell', (.048, width, .003), P(-.508, z, y), M['shield'], port, .001)
    for dz in [-width / 2, width / 2]:
        box('DETAIL__port_side', (.048, .003, .017), P(-.508, z + dz, .012), M['shield'], port)
    box('DETAIL__port_back', (.003, width, .018), P(-.485, z, .012), M['black'], port)
    box('DETAIL__port_tongue', (.036, width * .65, .003), P(-.505, z, .012), M['black'], port, .0008)
    for j in range(9):
        box('DETAIL__contact', (.014, .0014, .0004), P(-.513, z - width * .25 + j * width / 16, .0137), M['gold'], port, .0001)

# FPC connectors, copper flex and a bridge to the battery controller.
for x in [-.36, -.17, .035]:
    box('DETAIL__fpc_socket', (.085, .018, .006), P(x, .116, .005), M['black'], board)
    box('DETAIL__fpc_latch', (.085, .005, .003), P(x, .12, .009), M['ink'], board)
    for i in range(18):
        box('DETAIL__fpc_pin', (.002, .012, .001), P(x - .038 + i * .0043, .105, .004), M['gold'], board, .0002)
    box('DETAIL__flex', (.060, .065, .001), P(x, .155, .006), M['copper'], battery, .0004)
    for i in range(12):
        box('DETAIL__flex_track', (.001, .055, .0002), P(x - .024 + i * .0044, .155, .0067), M['gold'], battery, 0)

print('Six broad', flush=True)
# Six broad laminated pouches with folded perimeter seams and printed labels.
box('PART__battery__casing', (.865, .37, .008), P(0, .367, -.012), M['black'], battery, .008)
for row in range(2):
    for col in range(3):
        i = row * 3 + col
        x, z = -.286 + col * .286, .279 + row * .177
        box(f'PART__battery__pouch{i}', (.272, .163, .018), P(x, z, .001), M['battery'], battery, .006)
        for dz in [-.077, .077]:
            box('DETAIL__pouch_seal', (.258, .007, .0014), P(x, z + dz, .009), M['seam'], battery, .0006)
        for dx in [-.129, .129]:
            box('DETAIL__pouch_seal', (.006, .15, .0014), P(x + dx, z, .009), M['seam'], battery, .0006)
        text('Li-ion', x - .065, z - .015, .0103, .020, battery)
        text('RECHARGEABLE BATTERY', x, z + .019, .0103, .007, battery)
        text('DO NOT DISASSEMBLE   /   +', x, z + .036, .0103, .0055, battery)
        for j in range(22):
            box('DETAIL__barcode', (.0007 if j % 3 else .0015, .025, .0001), P(x + .05 + j * .0024, z - .022, .0103), M['ink'], battery, 0)

print('Batch decoration', flush=True)
# Batch decoration per immediate parent + material, preserving interactive roots.
batches = {}
bpy.context.view_layer.update()
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('DETAIL__'):
        key = (o.parent, o.data.materials[0])
        batches.setdefault(key, []).append(o)
for (parent, mat), objects in batches.items():
    if len(objects) == 1:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = 'DETAIL__' + mat.name.replace(' ', '_')

print('Validate the names', flush=True)
# Validate the names consumed by RealityKit before writing the asset.
for name in ['LAYER__board', 'LAYER__battery', 'LAYER__chassis', 'LAYER__lid', 'LAYER__silicon',
             'PART__chip__substrate', 'PART__memory__package0', 'PART__ssd__nand0', 'PART__power__port0']:
    assert bpy.data.objects.get(name) is not None, name
bpy.ops.object.select_all(action='SELECT')
Path(OUT).parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.usd_export(filepath=OUT, export_materials=True, export_animation=False,
                      export_textures_mode='NEW', generate_preview_surface=True, export_uvmaps=True,
                      selected_objects_only=False)
print('EXPORT_OK', OUT, 'meshes', sum(o.type == 'MESH' for o in scene.objects), flush=True)

if RENDER:
    silicon.hide_render = True
    for o in silicon.children_recursive:
        o.hide_render = True
    world = bpy.data.worlds.new('Studio')
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.15, .17, .20, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .4
    for loc, power, size in [((-.6, .1, 1.8), 140, 1.5), ((1.2, -.5, 1), 90, 1.0), ((0, 1.2, .8), 65, .8)]:
        bpy.ops.object.light_add(type='AREA', location=loc)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = 'DISK'
        light.data.size = size
        light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.object.camera_add(location=(.55, -1.15, 1.5))
    scene.camera = bpy.context.object
    scene.camera.rotation_euler = (Vector((0, -.10, 0)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera.data.type = 'ORTHO'
    scene.camera.data.ortho_scale = 1.65
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1200
    scene.render.resolution_percentage = 100
    scene.render.filepath = RENDER
    bpy.ops.render.render(write_still=True)

# These intermediate images are already embedded in USDZ.
for file in texture_dir.glob('*.png'):
    file.unlink()
texture_dir.rmdir()

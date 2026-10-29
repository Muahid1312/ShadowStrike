"""Original AR-01 model. Run: blender -b --factory-startup --python tools/build_rifle_asset.py
No third-party geometry/textures. Coordinates in this file are Godot metres, -Z forward.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/weapons/ar01'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
GROUPS = {}
def v(p): return Vector((p[0], -p[2], p[1]))
def material(name, color, metal, rough):
    m=bpy.data.materials.new(name);m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=(*color,1)
    b.inputs['Metallic'].default_value=metal;b.inputs['Roughness'].default_value=rough
    return m
MAT={
 'alloy':material('Anodized graphite',(.035,.048,.060),.78,.36),
 'steel':material('Machined steel edges',(.12,.15,.18),.85,.30),
 'polymer':material('Textured black polymer',(.011,.017,.023),.0,.73),
 'recess':material('Deep vents and bore',(.006,.009,.012),.1,.86),
 'glove':material('Olive tactical glove',(.105,.135,.082),.0,.84),
 'cloth':material('Woven sleeve and cuff',(.19,.225,.135),.0,.92),
 'mark':material('Laser markings',(.53,.56,.51),.35,.6),
}
def finish(obj, name, mat, group='Body', bevel=0):
    obj.name=name;obj.data.materials.clear();obj.data.materials.append(MAT[mat])
    if bevel:
        mod=obj.modifiers.new('Edge chamfer','BEVEL');mod.width=bevel;mod.segments=1
        mod.affect='EDGES'
        bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
    GROUPS.setdefault(group,[]).append(obj)
    return obj

def mesh(name, verts, faces, mat='alloy', group='Body', bevel=0):
    data=bpy.data.meshes.new(name);data.from_pydata([v(p) for p in verts],[],faces);data.update()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    return finish(obj,name,mat,group,bevel)

def box(name, center, size, mat='alloy', bevel=.0015, group='Body', tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=v(center));obj=bpy.context.object
    obj.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.rotation_euler.x=tilt
    return finish(obj,name,mat,group,bevel)

def profile(name, outline, width, mat='alloy', group='Body', bevel=.0015, x=0):
    # outline is a Y/Z side profile, extruded across X.
    n=len(outline);verts=[(x+s*width/2,y,z) for s in [-1,1] for y,z in outline]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,mat,group,bevel)

def cylinder(name,a,b,r,mat='steel',segments=12,group='Body',r2=None):
    d=v(b)-v(a);bpy.ops.mesh.primitive_cone_add(vertices=segments,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(v(a)+v(b))/2)
    obj=bpy.context.object;obj.rotation_mode='QUATERNION';obj.rotation_quaternion=Vector((0,0,1)).rotation_difference(d)
    for p in obj.data.polygons:p.use_smooth=len(p.vertices)==4
    return finish(obj,name,mat,group)

def tube(name,z1,z2,outer,inner,cy=0,mat='steel',segments=16):
    rings=[]
    for z,r in [(z1,outer),(z2,outer),(z2,inner),(z1,inner)]:
        rings += [(math.cos(i*math.tau/segments)*r,cy+math.sin(i*math.tau/segments)*r,z) for i in range(segments)]
    faces=[]
    for ring in range(4):
        for i in range(segments):
            j=(i+1)%segments; a=ring*segments; b=((ring+1)%4)*segments
            faces.append((a+i,a+j,b+j,b+i))
    return mesh(name,rings,faces,mat)

def loft(name, sections, mat='alloy',group='Body'):
    # Eight-point chamfered rectangular section in XZ, at each Y.
    verts=[]
    for y,z,w,l in sections:
        c=min(w,l)*.18
        verts += [(x,y,z+zz) for x,zz in [(-w/2+c,-l/2),(w/2-c,-l/2),(w/2,-l/2+c),(w/2,l/2-c),(w/2-c,l/2),(-w/2+c,l/2),(-w/2,l/2-c),(-w/2,-l/2+c)]]
    faces=[tuple(range(7,-1,-1)),tuple(range((len(sections)-1)*8,len(sections)*8))]
    for j in range(len(sections)-1):
        faces += [(j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i) for i in range(8)]
    return mesh(name,verts,faces,mat,group)

# Receiver: compact chamfered upper and sculpted lower; not a stack of large blocks.
profile('Forged upper receiver',[(.044,.092),(.052,.055),(.052,-.19),(.036,-.235),(-.025,-.235),(-.039,-.17),(-.039,.087)],.068,bevel=.004)
profile('Lower receiver',[(.003,.105),(.002,-.145),(-.076,-.13),(-.087,-.045),(-.053,.012),(-.05,.092)],.060,bevel=.004)
box('Receiver seam',(0,-.028,-.063),(.069,.002,.288),'steel',.0004)
# Left bolt plate, split charging handle, selector, take-down pins and engraved index marks.
box('Bolt catch',(-.036,-.018,-.028),(.010,.020,.025),'steel',.001)
for x in [-.038,.038]:
    for z in [-.14,.072]:cylinder('Receiver pin',(x-.002,-.025,z),(x+.002,-.025,z),.005,'steel',10)
    cylinder('Safety pivot',(x-.002,-.045,.039),(x+.002,-.045,.039),.006,'steel',10)
    box('Selector lever',(x,-.044,.025),(.008,.005,.028),'steel',.001)
    for zz in [.018,.057]:box('Selector index',(x,-.035,zz),(.001,.006,.0015),'mark',.0001)
box('Dust cover',(.036,.009,-.092),(.004,.033,.102),'polymer',.002)
box('Ejection-port bevel',(.039,.016,-.089),(.002,.017,.071),'recess',.001)
box('Charging latch',(0,.040,.102),(.092,.012,.024),'polymer',.002)
# Octagonal free-float handguard, barrel, gas block, front collar and open muzzle brake.
profile('Octagonal handguard',[(.038,-.235),(.038,-.515),(.024,-.547),(-.026,-.547),(-.039,-.515),(-.039,-.235)],.064,bevel=.005)
cylinder('Barrel',(0,0,-.53),(0,0,-.645),.011,'steel',16)
cylinder('Barrel shoulder',(0,0,-.535),(0,0,-.552),.017,'alloy',12)
tube('Muzzle brake bore',-.647,-.695,.016,.009,mat='steel',segments=16)
tube('Dark bore interior',-.653,-.693,.0092,.0083,mat='recess',segments=12)
for z in [-.659,-.677]:
    for x in [-.016,.016]:box('Brake gas port',(x,0,z),(.001,.012,.008),'recess',.0007)
# Vent and M-LOK slot insets, top rail and lower rail catches.
for side in [-1,1]:
    for i in range(6):
        z=-.264-i*.043
        box('MLOK inset',(side*.0326,-.008,z),(.002,.017,.030),'recess',.003)
        box('Vent bevel',(side*.033,.016,z),(.0015,.008,.026),'steel',.001)
    for z in [-.248,-.525]:cylinder('Handguard fastener',(side*.031,-.025,z),(side*.035,-.025,z),.0038,'steel',8)
box('Rail spine',(0,.055,-.218),(.025,.013,.595),'polymer',.001)
for i in range(27):
    box('Picatinny tooth',(0,.065,.071-i*.0215),(.035,.010,.012),'alloy',.001)
# Skeleton stock with angled cheek rest and rubberized shoulder pad.
cylinder('Buffer tube',(0,.005,.10),(0,.005,.250),.021,'alloy',16)
profile('Stock frame',[(.033,.16),(.034,.267),(-.089,.300),(-.117,.275),(-.076,.147)],.050,'polymer',bevel=.004)
profile('Stock opening',[(.012,.180),(.012,.245),(-.061,.260),(-.072,.203)],.051,'recess',bevel=.003)
profile('Cheek riser',[(.040,.135),(.041,.245),(.019,.270),(.006,.157)],.058,'alloy',bevel=.003)
profile('Rubber butt pad',[(.029,.274),(.023,.302),(-.105,.320),(-.123,.294)],.060,'polymer',bevel=.005)
for i in range(7):box('Butt-pad texture',(0,-.088+i*.015,.312-i*.002),(.060,.004,.003),'recess',.0004)
# Grip has a slanted profile, narrow trigger opening and a curved trigger.
profile('Pistol grip',[(-.053,.027),(-.061,.079),(-.190,.132),(-.212,.107),(-.198,.065)],.040,'polymer',bevel=.004)
for i in range(6):
    box('Grip stippling',(-.021,-.096-i*.015,.065+i*.005),(.0015,.004,.026),'recess',.001)
# Trigger guard is built as a slim loop, leaving the opening empty.
for a,b in [((0,-.072,-.046),(0,-.110,-.038)),((0,-.110,-.038),(0,-.117,.020)),((0,-.117,.020),(0,-.080,.036))]:
    cylinder('Trigger guard',a,b,.004,'alloy',8)
profile('Curved trigger',[(-.065,-.007),(-.087,-.011),(-.098,.001),(-.100,.009),(-.090,-.001),(-.066,.002)],.006,'steel',bevel=.0005)
# Tapered, visibly curved 30-round magazine, separate animation mesh.
mag_sections=[(-.057,-.080,.033,.082),(-.097,-.082,.033,.082),(-.154,-.098,.034,.078),(-.204,-.124,.034,.072),(-.241,-.150,.035,.070)]
loft('Curved magazine',mag_sections,'alloy','Magazine')
loft('Magazine floor plate',[(-.238,-.15,.037,.074),(-.249,-.151,.038,.076)],'polymer','Magazine')
for side in [-1,1]:
    for fraction in [-.28,0,.28]:
        verts=[]
        for y,z,w,l in mag_sections[1:]:
            verts += [(side*(w/2+.001),y,z+fraction*l-.002),(side*(w/2+.001),y,z+fraction*l+.002)]
        mesh('Magazine stamped rib',verts,[(2*j,2*j+1,2*j+3,2*j+2) for j in range(len(mag_sections)-2)],'steel','Magazine')
# Hollow compact red-dot hood. Thin frame keeps the center aim line clear.
# Four bevelled beams form the optic window, no opaque fake glass.
box('Optic base',(0,.083,-.005),(.046,.025,.073),'polymer',.003)
outer=[(-.028,.100),(-.028,.137),(-.020,.150),(.020,.150),(.028,.137),(.028,.100)]
inner=[(-.020,.107),(-.020,.135),(-.015,.143),(.015,.143),(.020,.135),(.020,.107)]
verts=[(x,y,z) for z,loop in [(-.034,outer),(.024,outer),(.024,inner),(-.034,inner)] for x,y in loop]
faces=[]
for ring in range(4):
    for i in range(6): faces.append((ring*6+i,ring*6+(i+1)%6,((ring+1)%4)*6+(i+1)%6,((ring+1)%4)*6+i))
mesh('Rounded optic hood',verts,faces,'alloy',bevel=.001)
cylinder('Optic battery cap',(.028,.113,.003),(.040,.113,.003),.014,'polymer',16)
cylinder('Optic adjustment',(-.028,.113,.003),(-.032,.113,.003),.009,'steel',12)
box('Adjustment screw',(-.033,.113,.003),(.001,.0018,.012),'recess',.0002)
# Small front sight tower and post; mounting shape stays below optic axis.
profile('Front sight support',[(.041,-.508),(.094,-.496),(.094,-.480),(.040,-.470)],.014,'polymer',bevel=.002)
box('Front sight post',(0,.111,-.490),(.004,.031,.004),'steel',.0005)
# Original gloves: rounded palms, segmented fingers, cuffs and sleeves.
def hand(name,center,group,support=False):
    x,y,z=center
    box(name+' palm',(x,y,z),(.062,.035,.069) if support else (.047,.065,.047),'glove',.010,group)
    if support:
        for i in range(4):
            zz=z-.025+i*.016
            cylinder('Finger underside',(x-.018,y-.012,zz),(x+.029,y-.011,zz),.008,'glove',8,group)
            cylinder('Finger curl',(x+.029,y-.011,zz),(x+.031,y+.020,zz),.008,'glove',8,group)
            box('Knuckle pad',(x-.022,y+.006,zz),(.018,.014,.012),'polymer',.003,group)
        cylinder('Support thumb',(x-.028,y+.006,z+.025),(x-.026,y+.033,z+.002),.010,'glove',8,group)
    else:
        for i in range(3):
            yy=y-.022+i*.018
            cylinder('Grip finger',(x+.017,yy,z-.016),(x-.014,yy,z-.021),.0085,'glove',8,group)
        cylinder('Trigger finger',(x-.013,y+.027,z-.015),(x-.007,y+.027,z-.058),.007,'glove',8,group)
        cylinder('Firing thumb',(x+.024,y+.010,z+.015),(x+.018,y+.036,z-.010),.009,'glove',8,group)
hand('Support glove',(-.008,-.065,-.387),'SupportHand',True)
hand('Firing glove',(.011,-.135,.083),'FiringHand')
cylinder('Firing sleeve unit',(0,0,0),(0,0,-.5),.055,'cloth',10,'FiringForearm',r2=.035)
cylinder('Firing cuff unit',(0,0,-.45),(0,0,-.5),.038,'glove',10,'FiringForearm')
# A separate unit forearm can follow the support hand during reload without stretching fingers.
cylinder('Support sleeve unit',(0,0,0),(0,0,-.5),.052,'cloth',10,'SupportForearm',r2=.035)
cylinder('Support cuff unit',(0,0,-.45),(0,0,-.5),.038,'glove',10,'SupportForearm')
# Small laser marking uses the already licensed project heading font; converted to geometry.
font=bpy.data.fonts.load(str(ROOT/'assets/fonts/Heading.ttf'))
for side in [-1,1]:
    data=bpy.data.curves.new('AR-01 marking','FONT');data.body='AR-01';data.font=font;data.size=.009;data.extrude=0
    obj=bpy.data.objects.new('Laser serial',data);bpy.context.collection.objects.link(obj)
    # Text local x follows gun length, local y is vertical, face points outward.
    gx=Vector((0,0,1 if side<0 else -1));gy=Vector((0,1,0));gz=gx.cross(gy)
    obj.matrix_world=Matrix((v(gx),v(gy),v(gz))).transposed().to_4x4();obj.location=v((side*.0355,.014,-.164 if side<0 else -.113))
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj;bpy.ops.object.convert(target='MESH')
    finish(bpy.context.object,'Laser serial','mark')
# Batch disconnected detail geometry by moving component; glTF emits one surface/material.
pivots={'Magazine':(0,-.06,-.08),'SupportHand':(-.008,-.065,-.387),'SupportForearm':(-.185,-.28,.20),'FiringHand':(.011,-.135,.083),'FiringForearm':(.136,-.297,.249)}
stats={}
for group,objects in GROUPS.items():
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=group
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    point=v(pivots.get(group,(0,0,0)))
    if group not in ['SupportForearm','FiringForearm']:
        for vert in obj.data.vertices:vert.co-=point
    obj.location=point
    obj.data.update();obj.data.calc_loop_triangles()
    stats[group]={'triangles':len(obj.data.loop_triangles),'vertices':len(obj.data.vertices),'materials':len(set(m.name for m in obj.data.materials))}
# Repair winding and write useful imported locator names.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
root=bpy.data.objects.new('AR01',None);bpy.context.collection.objects.link(root)
for obj in list(bpy.context.scene.objects):
    if obj!=root:obj.parent=root
for name,point in [('Muzzle',(0,0,-.700)),('OpticAxis',(0,.125,-.005)),('SupportElbow',(-.185,-.28,.20))]:
    obj=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(obj);obj.location=v(point);obj.parent=root
bpy.ops.export_scene.gltf(filepath=str(OUT/'AR01.glb'),export_format='GLB',use_selection=False,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,export_apply=True,export_materials='EXPORT')
(OUT/'geometry_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
print('AR01_GEOMETRY',json.dumps(stats),'TOTAL',sum(s['triangles'] for s in stats.values()))

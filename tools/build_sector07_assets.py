"""Original compound kit + explicitly licensed cargo adaptation. Run with Blender4.3.2.
blender -b --factory-startup --python tools/build_sector07_assets.py -- --tps-source /path/to/tps-demo-master
"""
import bpy,math,json,random,sys,struct,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/sector07';TEX=OUT/'textures';OUT.mkdir(parents=True,exist_ok=True)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source=Path(args[args.index('--tps-source')+1]) if '--tps-source' in args else Path('/tmp/sector07-tps/tps-demo-master')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
# Crop the original licensed cargo mesh; strip all unrelated source scene geometry.
bpy.ops.import_scene.gltf(filepath=str(source/'level/geometry/models/props.glb'))
obj=bpy.data.objects['prop_cargobox3.001'];data=obj.data.copy()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
obj=bpy.data.objects.new('CargoCrate',data);bpy.context.collection.objects.link(obj)
# Imported geometry is Blender Z-up. Normalize to unit extent, bottom-centered for instances.
lo=Vector([min(v.co[i] for v in data.vertices) for i in range(3)]);hi=Vector([max(v.co[i] for v in data.vertices) for i in range(3)])
for vtx in data.vertices:
 vtx.co=Vector(((vtx.co.x-(lo.x+hi.x)/2)/(hi.x-lo.x),(vtx.co.y-(lo.y+hi.y)/2)/(hi.y-lo.y),(vtx.co.z-lo.z)/(hi.z-lo.z)))
mat=bpy.data.materials.new('TPS cargo / CC-BY3');mat.use_nodes=True;nodes=mat.node_tree.nodes;bs=nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.8
for kind in ['albedo','normal','orm']:
 p=source/f'level/textures/props/mid_cargo_box_{kind}.png';image=bpy.data.images.load(str(p));image.colorspace_settings.name='sRGB' if kind=='albedo' else 'Non-Color';image.scale(1024,1024);image.filepath_raw=str(TEX/f'cargo_{kind}.png');image.file_format='PNG';image.save()
 node=nodes.new('ShaderNodeTexImage');node.image=image
 if kind=='albedo':mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
 else:
  image.colorspace_settings.name='Non-Color'
  if kind=='normal':
   normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.7;mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
  else:
   split=nodes.new('ShaderNodeSeparateColor');mat.node_tree.links.new(node.outputs['Color'],split.inputs[0]);mat.node_tree.links.new(split.outputs['Green'],bs.inputs['Roughness']);mat.node_tree.links.new(split.outputs['Blue'],bs.inputs['Metallic'])
obj.data.materials.clear();obj.data.materials.append(mat)
for poly in obj.data.polygons:poly.material_index=0
bpy.ops.export_scene.gltf(filepath=str(OUT/'cargo.glb'),export_format='GLB',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
# Original architecture follows; Godot metres with -Z north.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
GROUPS={};C=[];MAT={};rng=random.Random(707)
def v(p):return Vector((p[0],-p[2],p[1]))
def material(name,color,rough=.85,metal=0,texture=None):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
 if texture:
  for kind in ['albedo','normal']:
   im=bpy.data.images.load(str(TEX/f'{texture}_{kind}.png'),check_existing=True);n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=im
   if kind=='albedo':
    mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*color,1);m.node_tree.links.new(n.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
   else:
    im.colorspace_settings.name='Non-Color';norm=m.node_tree.nodes.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.45;m.node_tree.links.new(n.outputs['Color'],norm.inputs['Color']);m.node_tree.links.new(norm.outputs['Normal'],b.inputs['Normal'])
 MAT[name]=m
material('concrete',(.32,.35,.35),texture='concrete')
material('stucco',(.38,.34,.28),texture='concrete')
material('dark_concrete',(.11,.13,.14),texture='concrete')
material('blue_steel',(.065,.11,.14),.55,.62)
material('zinc',(.25,.29,.30),.46,.75)
material('rubber',(.015,.022,.027),.9)
material('wood',(.62,.40,.19),texture='wood')
material('sandbag',(.39,.33,.23),texture='canvas')
material('stripe',(.67,.48,.16),.8)
material('berm',(.43,.36,.25),texture='dirt')
material('rock',(.065,.085,.095),texture='concrete')
def finish(obj,name,mat,group,bevel=0):
 obj.name=name;obj.data.materials.clear();obj.data.materials.append(MAT[mat])
 if bevel:
  mod=obj.modifiers.new('Edge chamfer','BEVEL');mod.width=bevel;mod.segments=1;bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
 GROUPS.setdefault(group,[]).append(obj);return obj

def box(name,p,size,mat='concrete',group='Yard',collide=False,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=v(p));o=bpy.context.object;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 finish(o,name,mat,group,min(bevel,min(size)*.18))
 if collide:C.append({'name':name,'shape':'box','position':p,'size':size})
 return o

def mesh(name,verts,faces,mat,group):
 d=bpy.data.meshes.new(name);d.from_pydata([v(x) for x in verts],[],faces);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);return finish(o,name,mat,group)
def beam(name,a,b,r=.035,mat='zinc',group='Tower'):
 delta=v(b)-v(a);bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r,depth=delta.length,location=(v(a)+v(b))/2);o=bpy.context.object;o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector((0,0,1)).rotation_difference(delta);return finish(o,name,mat,group)
def wall_line(name,p,length,axis,height,openings,group,mat):
 # Each opening (center,width,sill,top) is real geometry and matching box collision.
 bounds={-length/2,length/2}
 for c,w,sill,top in openings:bounds.update([c-w/2,c+w/2])
 bounds=sorted(bounds)
 for a,b in zip(bounds,bounds[1:]):
  mid=(a+b)/2;hole=next((o for o in openings if o[0]-o[1]/2<mid<o[0]+o[1]/2),None)
  spans=[(0,height)] if hole is None else [(0,hole[2]),(hole[3],height)]
  for low,high in spans:
   if high-low<.01:continue
   pos=list(p);pos[axis]+=mid;pos[1]=(low+high)/2
   size=[.24,high-low,.24];size[axis]=b-a
   box(name,pos,size,mat,group,True,.018)
 # Thin painted surrounds add depth without filling the openings.
 for c,w,sill,top in openings:
  for offset,y,span in [(-w/2,(sill+top)/2,(.08,top-sill+.16)),(w/2,(sill+top)/2,(.08,top-sill+.16)),(0,top,(w+.16,.10))]:
   pos=list(p);pos[axis]+=c+offset;pos[1]=y;size=[.32,span[1],.32];size[axis]=span[0];box('Opening surround',pos,size,'blue_steel',group,False,.01)

def building(name,cx,cz,width,depth,height,mat,garage=False):
 g=name
 # Floor flush to the arena avoids unintentional steps in the unchanged controller.
 box('Building floor',(cx,-.035,cz),(width,.07,depth),'dark_concrete',g,False)
 front=[(0,2.2,0,2.5),(-width*.32,1.3,1.2,2.4),(width*.32,1.3,1.2,2.4)]
 wall_line('Front wall',(cx,0,cz+depth/2),width,0,height,front,g,mat)
 wall_line('Rear wall',(cx,0,cz-depth/2),width,0,height,[(0,2.0,0,2.5)],g,mat)
 wall_line('West wall',(cx-width/2,0,cz),depth,2,height,[(0,4.2 if garage else 1.9,0,2.75 if garage else 2.5)],g,mat)
 wall_line('East wall',(cx+width/2,0,cz),depth,2,height,[(-depth*.25,1.4,1.25,2.4),(depth*.25,1.4,1.25,2.4)],g,mat)
 # Fascia, visible roof membrane, parapets and drainage.
 box('Roof slab',(cx,height+.08,cz),(width+.4,.16,depth+.4),'blue_steel',g,True)
 for z in [cz-depth/2,cz+depth/2]:box('Roof fascia',(cx,height-.12,z),(width+.38,.24,.20),'zinc',g)
 for x in [cx-width/2,cx+width/2]:box('Roof fascia',(x,height-.12,cz),(.20,.24,depth+.38),'zinc',g)
 for x in [cx-width/2+.12,cx+width/2-.12]:
  beam('Drain pipe',(x,.1,cz+depth/2+.18),(x,height-.2,cz+depth/2+.18),.045,'zinc',g)
 # Door parked open beside the front opening; no fake closed doorway.
 box('Open steel door',(cx-1.20,1.2,cz+depth/2-.5),(.08,2.4,1.04),'blue_steel',g,True)
 box('Ventilator housing',(cx+width/2-.5,height+.40,cz-depth/4),(1.0,.55,1.1),'zinc',g)
 for i in range(6):box('Vent slat',(cx+width/2-.5,height+.4,cz-depth/4+.57-i*.02),(.82,.04,.016),'rubber',g,False,.002)
 if garage:
  for i in range(8):box('Raised shutter',(cx-width/2-.14,2.9+i*.05,cz),(.12,.035,4.25),'zinc',g,False,.004)
  box('Service workbench',(cx+2.7,.85,cz-2.6),(1.8,.12,.7),'wood',g,True)
  for x in [cx+2,cx+3.4]:box('Workbench leg',(x,.41,cz-2.6),(.08,.82,.55),'blue_steel',g)
 # Recessed service band and exterior corner pads break broad wall repetition.
 for z in [cz-depth/2,cz+depth/2]:box('Foundation band',(cx,.18,z),(width,.36,.28),'dark_concrete',g)
 # Foundation bands must not close actual doors: decorative strips omit the central gap.
 # Remove full front/back strip and replace it with side segments below window sills.
 for o in list(GROUPS[g]):
  if o.name.startswith('Foundation band'):
   GROUPS[g].remove(o);bpy.data.objects.remove(o,do_unlink=True)
 for z in [cz-depth/2,cz+depth/2]:
  for side in [-1,1]:box('Foundation trim',(cx+side*(width/4+.65),.18,z),(width/2-1.3,.36,.28),'dark_concrete',g)

building('HQ',-18,-12,8,8,3.6,'stucco')
box('HQ apron',(-18,-.035,-6),(8,.08,4),'concrete','HQ',False)
box('Safety board',(-20.5,1.8,-15.82),(1.9,1.15,.06),'blue_steel','HQ',False,.025)
building('Workshop',18,-1,8,8,3.8,'concrete',True)
box('Workshop vehicle apron',(11.5,-.035,-1),(5,.08,9),'concrete','Workshop',False)
building('Barracks',-17.5,17,8,7,3.3,'stucco')
box('Barracks approach',(-17.5,-.035,12.5),(8,.08,2),'concrete','Barracks',False)
# Real security boundary; a lower plinth plus open metal fence creates varied silhouettes.
for side in [-1,1]:
 box('Perimeter plinth',(side*24,1.5,0),(.35,3,48),'concrete','Perimeter',False)
 C.append({'name':'Compound boundary','shape':'box','position':(side*24,2.9,0),'size':(.35,5.8,48.5)})
 for z in range(-24,25,4):
  box('Boundary pier',(side*24,1.65,z),(.55,3.3,.48),'dark_concrete','Perimeter')
  beam('Fence upright',(side*24,3,z),(side*24,5.8,z),.045,'blue_steel','Perimeter')
 for y in [3.25,4.4,5.75]:beam('Fence rail',(side*24,y,-24),(side*24,y,24),.025,'zinc','Perimeter')
 for z in range(-23,24,1):beam('Security picket',(side*24,3.15,z),(side*24,5.7,z),.012,'zinc','Perimeter')
for side in [-1,1]:
 box('Perimeter end plinth',(0,1.5,side*24),(48,3,.35),'concrete','Perimeter')
 C.append({'name':'Compound boundary','shape':'box','position':(0,2.9,side*24),'size':(48.5,5.8,.35)})
 for x in range(-24,25,4):
  box('Boundary pier',(x,1.65,side*24),(.48,3.3,.55),'dark_concrete','Perimeter');beam('Fence upright',(x,3,side*24),(x,5.8,side*24),.045,'blue_steel','Perimeter')
 for y in [3.25,4.4,5.75]:beam('Fence rail',(-24,y,side*24),(24,y,side*24),.025,'zinc','Perimeter')
 for x in range(-23,24,1):beam('Security picket',(x,3.15,side*24),(x,5.7,side*24),.012,'zinc','Perimeter')
# Jersey barriers use actual tapered profiles and simple convex matching collision.
for cx,cz,length in [(-6,-9,4.5),(5,2,4.5),(0,-17,4.5),(0,12,4.2)]:
 cross=[(-.45,0),(.45,0),(.45,.20),(.22,.78),(.15,1.3),(-.15,1.3),(-.22,.78),(-.45,.2)]
 verts=[(cx+s*length/2,y,cz+z) for s in [-1,1] for z,y in cross];n=len(cross)
 mesh('Cast jersey barrier',verts,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'concrete','Barriers')
 C.append({'name':'Jersey barrier','shape':'convex','points':verts})
 for i in range(int(length/.45)):
  box('Barrier warning paint',(cx-length/2+.23+i*.45,.99,cz+.172),(.20,.24,.008),'stripe','Barriers',False,.001)
# Walkable tower with solid platform, real stair ramp and a railing opening at the landing.
for x in [15.2,18.8]:
 for z in [-18.8,-15.2]:box('Tower support',(x,2.05,z),(.22,4.1,.22),'blue_steel','Tower',True)
for x in [15.2,18.8]:
 for a,b in [((x,.2,-18.8),(x,3.85,-15.2)),((x,.2,-15.2),(x,3.85,-18.8))]:beam('Tower X brace',a,b,.045,'zinc','Tower')
box('Observation platform',(17,4.08,-17),(4.45,.24,4.45),'dark_concrete','Tower',True)
box('Stair landing',(14.3,4.10,-16.7),(1.6,.20,1.65),'blue_steel','Tower',True)
for x in [14.85,19.15]:
 for z in [-19.15,-14.85]:box('Canopy post',(x,5.50,z),(.10,2.6,.10),'blue_steel','Tower',True)
# Slightly pitched canopy, with folded fascias.
roof=box('Tower canopy',(17,6.80,-17),(5.15,.14,5.1),'blue_steel','Tower');roof.rotation_euler.x=.045
C.append({'name':'Tower canopy','shape':'box','position':(17,6.80,-17),'size':(5.15,.20,5.1)})
for x in [14.45,19.55]:box('Canopy trim',(x,6.77,-17),(.12,.22,5.1),'zinc','Tower')
for a,b in [((14.85,5.2,-19.15),(19.15,5.2,-19.15)),((19.15,5.2,-19.15),(19.15,5.2,-14.85)),((19.15,5.2,-14.85),(14.85,5.2,-14.85)),((14.85,5.2,-19.15),(14.85,5.2,-17.6)),((14.85,5.2,-15.8),(14.85,5.2,-14.85))]:
 beam('Tower railing',a,b,.035,'zinc','Tower');mid=[(a[i]+b[i])/2 for i in range(3)];size=[abs(a[i]-b[i])+.07 for i in range(3)];size[1]=1.05;mid[1]=4.70;C.append({'name':'Tower rail','shape':'box','position':mid,'size':size})
 for t in [.15,.5,.85]:
  p=[a[i]+(b[i]-a[i])*t for i in range(3)];beam('Railing baluster',(p[0],4.2,p[2]),p,.022,'zinc','Tower')
for i in range(22):
 t=(i+1)/22;y=4.2*t;z=-8.5-7.4*t
 box('Steel stair tread',(14.3,y-.035,z+.168),(1.35,.07,.36),'blue_steel','Tower',False,.012)
 box('Stair nosing',(14.3,y+.002,z+.33),(1.25,.018,.025),'stripe','Tower',False,.003)
points=[(x,y,z) for x in [13.625,14.975] for y,z in [(0,-8.5),(0,-15.9),(4.2,-15.9)]]
C.append({'name':'Walkable stairs','shape':'convex','points':points})
for x in [13.65,14.95]:
 C.append({'name':'Stair rail','shape':'convex','points':[(xx,yy,zz) for xx in [x-.035,x+.035] for yy,zz in [(.3,-8.5),(1.05,-8.5),(5.25,-15.9),(4.5,-15.9)]]})
 beam('Stair stringer',(x,.03,-8.5),(x,4.1,-15.9),.065,'blue_steel','Tower')
 beam('Stair handrail',(x,1.02,-8.5),(x,5.22,-15.9),.03,'zinc','Tower')
 for t in [0,.25,.5,.75,1]:beam('Stair baluster',(x,4.2*t,-8.5-7.4*t),(x,4.2*t+1.02,-8.5-7.4*t),.022,'zinc','Tower')
# Original curved low-resolution rock formations, not cuboid mountains.
for section in range(4):
 verts=[];nx,nz=60,11
 for j in range(nz):
  for i in range(nx):
   xx=-100+i*200/(nx-1);zz=-33-j*12
   peak=12+5*math.sin(xx*.027+section*.8)+3*math.sin(xx*.081+section)
   yy=max(0,math.sin(j/(nz-1)*math.pi)*peak + math.sin(xx*.13+j*.48)*1.7 + math.sin(xx*.31-j*.8)*.65)
   px,pz=(xx,zz) if section==0 else ((zz,xx) if section==1 else ((-zz,xx) if section==2 else (xx,-zz)))
   verts.append((px,yy-1,pz))
 faces=[(j*nx+i,j*nx+i+1,(j+1)*nx+i+1,(j+1)*nx+i) for j in range(nz-1) for i in range(nx-1)]
 hill=mesh('Desert escarpment',verts,faces,'rock','Background')
 for poly in hill.data.polygons:poly.use_smooth=True
# Earthen backstop north of the working target lines.
verts=[]
for x in range(-15,16):
 for z,y in [(-21.8,0),(-23.0,2.4+rng.random()*.4),(-25.3,.1)]:verts.append((x,y,z))
mesh('Range backstop',verts,[(i*3+j,(i+1)*3+j,(i+1)*3+j+1,i*3+j+1) for i in range(30) for j in range(2)],'berm','Range')
# Small original prop kit: ribbed barrel, sandbag, pallet; instantiated by the map.
# Build unit barrel by ring loft.
rings=[(0,.34),(.04,.37),(.15,.36),(.2,.38),(.25,.36),(.78,.36),(.83,.38),(.88,.36),(1.0,.37),(1.04,.34)]
verts=[(math.cos(i*math.tau/20)*r,y,math.sin(i*math.tau/20)*r) for y,r in rings for i in range(20)]
faces=[tuple(range(19,-1,-1)),tuple(range((len(rings)-1)*20,len(rings)*20))]+[(j*20+i,j*20+(i+1)%20,(j+1)*20+(i+1)%20,(j+1)*20+i) for j in range(len(rings)-1) for i in range(20)]
mesh('FuelDrum',verts,faces,'blue_steel','FuelDrum')
box('Sandbag',(0,.14,0),(.70,.28,.38),'sandbag','Sandbag',False,.105)
# Range target stand and stencil board. Hitbox remains managed by the existing target script.
beam('Target stand',(0,.05,0),(0,1.2,0),.045,'zinc','TargetFrame')
for x in [-.45,.45]:box('Target foot',(x,.05,0),(.08,.10,.65),'blue_steel','TargetFrame',False,.015)
box('Target crossbar',(0,.12,0),(.95,.08,.08),'blue_steel','TargetFrame',False,.012)
box('Plate',(0,1.85,0),(.95,1.7,.05),'stucco','TargetPlate',False,.04)
# Human stencil in relief avoids alpha textures and retains the old full-board hit extent.
verts=[(-.15,2.55,.029),(.15,2.55,.029),(.19,2.3,.029),(.36,2.16,.029),(.36,1.8,.029),(.22,1.6,.029),(.20,1.1,.029),(-.20,1.1,.029),(-.22,1.6,.029),(-.36,1.8,.029),(-.36,2.16,.029),(-.19,2.3,.029)]
mesh('Target stencil',verts,[tuple(range(12))],'rubber','TargetPlate')
box('Target center',(0,1.72,.036),(.16,.21,.005),'stripe','TargetPlate',False,.02)
# Batch by spatial chunk/material; world-projected UVs provide consistent texel density.
stats={}
def fix_material_factors(path):
 # The installed glTF exporter omits a constant multiply after an image node.
 # Preserve that authored tint explicitly using standard glTF PBR factors.
 data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0]
 graph=json.loads(data[20:20+length]);binary=data[20+length:]
 for m in graph.get('materials',[]):
  if m['name'] in MAT:
   color=MAT[m['name']].node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value
   m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=list(color)
 # Share identical embedded image sources across tinted materials.
 unique=[];lookup={};mapping={};payload=binary[8:]
 for index,image in enumerate(graph.get('images',[])):
  view=graph['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
  key=hashlib.sha256(payload[start:start+view['byteLength']]).hexdigest()
  if key not in lookup:lookup[key]=len(unique);unique.append(image)
  mapping[index]=lookup[key]
 for texture in graph.get('textures',[]):texture['source']=mapping[texture['source']]
 graph['images']=unique
 encoded=json.dumps(graph,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+binary)
def export_groups(groups,path):
 bpy.ops.object.select_all(action='DESELECT');objects=[]
 for group in groups:
  items=GROUPS[group]
  bpy.ops.object.select_all(action='DESELECT')
  for ob in items:ob.select_set(True)
  bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=group
  bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  uv=ob.data.uv_layers.new(name='WorldProjected')
  for poly in ob.data.polygons:
   axis=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3) if i!=axis]
   for li in poly.loop_indices:
    co=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*.55,co[axes[1]]*.55)
  ob.data.calc_loop_triangles();stats[group]={'triangles':len(ob.data.loop_triangles),'surfaces':len(set(m.name for m in ob.data.materials))};objects.append(ob)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in objects:ob.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.export_scene.gltf(filepath=str(OUT/path),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_lights=False,export_cameras=False)
 fix_material_factors(OUT/path)
export_groups(['HQ','Workshop','Barracks','Perimeter','Barriers','Tower','Background','Range'],'compound.glb')
export_groups(['FuelDrum','Sandbag','TargetFrame','TargetPlate'],'props.glb')
(OUT/'collision_layout.json').write_text(json.dumps(C,indent=2)+'\n')
(OUT/'geometry_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
print('SECTOR07',json.dumps(stats),'COLLIDERS',len(C))

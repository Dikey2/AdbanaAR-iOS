import os, subprocess, sys, math
# (asset, x, y, z, rotY grados, rotX grados, escala)
ESCENAS = {
 'torta_zanahoria': [('carved_wooden_plate',0,0,0,0,0,1), ('carrot_cake',0,0.011,0,30,0,1)],
 'torta_chocolate_fresas': [('carved_wooden_plate',0,0,0,0,0,1.25), ('strawberry_chocolate_cake',0,0.013,0,0,0,1)],
 'croissants': [('carved_wooden_plate',0,0,0,0,0,1), ('croissant',-0.005,0.010,0.042,12,0,1), ('croissant',0.008,0.010,-0.045,-8,0,0.95)],
 'bowl_frutas': [('wooden_bowl_01',0,0,0,0,0,1),
   ('food_pomegranate_01',-0.045,0.018,-0.035,20,0,1), ('food_apple_01',0.055,0.016,-0.03,0,0,1),
   ('food_kiwi_01',0.0,0.02,0.07,0,0,1), ('food_lime_01',-0.08,0.03,0.04,40,0,1),
   ('lemon',0.07,0.058,0.055,30,0,1), ('food_lychee_01',0.01,0.02,-0.095,0,0,1),
   ('food_lychee_01',-0.025,0.03,0.015,80,30,1), ('food_lychee_01',0.035,0.025,0.035,20,0,1)],
 'tabla_frutas': [('wooden_cutting_board',0,0,0,0,0,1),
   ('food_avocado_01',-0.15,0.041,0.0,0,0,1), ('food_pomegranate_01',-0.05,0.041,0.03,0,0,1),
   ('food_apple_01',0.06,0.041,-0.04,30,0,1), ('food_kiwi_01',0.05,0.041,0.065,0,0,1),
   ('lemon',0.145,0.093,0.04,0,0,1), ('food_lime_01',0.165,0.041,-0.06,0,0,1),
   ('food_lychee_01',-0.06,0.041,-0.08,0,0,1), ('food_lychee_01',-0.1,0.041,-0.075,50,0,1)],
}
def usda(nombre, piezas, camara):
    out = ['#usda 1.0\n(\n    defaultPrim = "Root"\n    metersPerUnit = 1\n    upAxis = "Y"\n)\ndef Xform "Root"\n{']
    for i,(a,x,y,z,ry,rx,s) in enumerate(piezas):
        out.append(f'''    def Xform "p{i}_{a}" (
        prepend references = @../out/{a}.usdz@
    )
    {{
        double3 xformOp:translate = ({x}, {y}, {z})
        float xformOp:rotateY = {ry}
        float xformOp:rotateX = {rx}
        float3 xformOp:scale = ({s}, {s}, {s})
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateY", "xformOp:rotateX", "xformOp:scale"]
    }}''')
    k = 1.5 if nombre == 'tabla_frutas' else 1.0
    if camara:
        out.append(f'''    def Camera "cam"
    {{
        float focalLength = 50
        float horizontalAperture = 36
        float verticalAperture = 36
        float2 clippingRange = (0.01, 100)
        double3 xformOp:translate = (0, {0.42*k:.3f}, {0.52*k:.3f})
        float xformOp:rotateX = -38
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateX"]
    }}''')
    out.append('}\n')
    return '\n'.join(out)
os.makedirs('esc', exist_ok=True)
for n,p in ESCENAS.items():
    if len(sys.argv)>1 and n not in sys.argv[1:]: continue
    open(f'esc/{n}_prev.usda','w').write(usda(n,p,True))
    open(f'esc/{n}.usda','w').write(usda(n,p,False))
    subprocess.run(['usdcat','--flatten',f'esc/{n}.usda','-o',f'esc/{n}_flat.usdc'],check=True)
    o=os.path.abspath(f'out_esc/{n}.usdz'); os.makedirs('out_esc',exist_ok=True)
    if os.path.exists(o): os.remove(o)
    r=subprocess.run(['usdzip','-a',f'{n}_flat.usdc',o],cwd='esc',capture_output=True,text=True)
    subprocess.run(['usdrecord','--camera','/Root/cam','--imageWidth','500',f'esc/{n}_prev.usda',f'prev/esc_{n}.png'],capture_output=True)
    c=subprocess.run(['usdchecker','--arkit',o],capture_output=True,text=True)
    print(n, os.path.getsize(o) if os.path.exists(o) else 'NOFILE', 'OK' if 'Success' in c.stdout+c.stderr else (c.stdout+c.stderr)[-300:])

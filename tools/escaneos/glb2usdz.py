# GLB (glTF 2.0) -> USDZ para RealityKit, sin dependencias externas.
# Uso: python3 glb2usdz.py entrada.glb salida.usdz ancho_m [rotX] [rotY] [rotZ]
# Hornea las transformaciones de nodos, normaliza a escala real (mayor medida horizontal = ancho_m),
# apoya la base en y=0, centra en x/z, voltea V de las UV y reduce texturas a 1024 px (JPG/PNG).
import json, struct, sys, os, math, shutil, subprocess, base64

src, dst, ancho = sys.argv[1], sys.argv[2], float(sys.argv[3])
rot = [float(x) for x in sys.argv[4:7]] + [0.0] * (3 - len(sys.argv[4:7]))
data = open(src, 'rb').read()
assert data[:4] == b'glTF'
off = 12; js = None; binc = b''
while off < len(data):
    ln, typ = struct.unpack_from('<I4s', data, off); off += 8
    chunk = data[off:off + ln]; off += ln
    if typ == b'JSON': js = json.loads(chunk)
    elif typ == b'BIN\x00': binc = chunk
G = js
COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NUM = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def bview(i):
    bv = G['bufferViews'][i]
    return binc[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']], bv.get('byteStride')

def accessor(i):
    a = G['accessors'][i]; fmt, sz = COMP[a['componentType']]; n = NUM[a['type']]
    if 'bufferView' not in a: return [[0.0] * n for _ in range(a['count'])]
    buf, stride = bview(a['bufferView']); base = a.get('byteOffset', 0)
    stride = stride or sz * n
    out = []
    norm = a.get('normalized', False)
    for k in range(a['count']):
        v = struct.unpack_from('<' + fmt * n, buf, base + k * stride)
        if norm and fmt in 'BH': v = tuple(x / (255.0 if fmt == 'B' else 65535.0) for x in v)
        out.append(v)
    return out

def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def node_matrix(n):
    if 'matrix' in n:
        m = n['matrix']; return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = n.get('translation', [0, 0, 0]); q = n.get('rotation', [0, 0, 0, 1]); s = n.get('scale', [1, 1, 1])
    x, y, z, w = q
    R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[R[r][0] * s[0], R[r][1] * s[1], R[r][2] * s[2], t[r]] for r in range(3)] + [[0, 0, 0, 1]]

def rot_matrix(rx, ry, rz):
    def X(a): c, s = math.cos(a), math.sin(a); return [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]]
    def Y(a): c, s = math.cos(a), math.sin(a); return [[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]]
    def Z(a): c, s = math.cos(a), math.sin(a); return [[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    return matmul(Z(math.radians(rz)), matmul(Y(math.radians(ry)), X(math.radians(rx))))

I4 = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
prims = []  # (matriz, primitive)
def walk(ni, parent):
    n = G['nodes'][ni]; m = matmul(parent, node_matrix(n))
    if 'mesh' in n:
        for p in G['meshes'][n['mesh']]['primitives']:
            if p.get('mode', 4) == 4: prims.append((m, p))
    for c in n.get('children', []): walk(c, m)
scene = G['scenes'][G.get('scene', 0)]
RootM = rot_matrix(*rot)
for ni in scene['nodes']: walk(ni, RootM)

def xf(m, v, w=1.0):
    return [m[r][0] * v[0] + m[r][1] * v[1] + m[r][2] * v[2] + m[r][3] * w for r in range(3)]

geo = []
for m, p in prims:
    a = p['attributes']
    pts = [xf(m, v) for v in accessor(a['POSITION'])]
    nrm = None
    if 'NORMAL' in a:
        nrm = []
        for v in accessor(a['NORMAL']):
            t = xf(m, v, 0.0); L = math.sqrt(sum(x * x for x in t)) or 1.0
            nrm.append([x / L for x in t])
    uv = [(u, 1.0 - v) for u, v in accessor(a['TEXCOORD_0'])] if 'TEXCOORD_0' in a else None
    idx = [i[0] for i in accessor(p['indices'])] if 'indices' in p else list(range(len(pts)))
    # determinante negativo invierte la orientación de las caras
    det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    if det < 0:
        for k in range(0, len(idx) - 2, 3): idx[k + 1], idx[k + 2] = idx[k + 2], idx[k + 1]
    geo.append(dict(pts=pts, nrm=nrm, uv=uv, idx=idx, mat=p.get('material')))

# recorte opcional: quita triángulos bajo una fracción de la altura (pedestales escaneados)
corte = float(os.environ.get('CORTE', '0'))
radio = float(os.environ.get('RADIO', '0'))  # fracción del ancho: quita lo que esté fuera de ese radio
if corte > 0 or radio > 0:
    ys0 = [q[1] for g in geo for q in g['pts']]; y0, y1 = min(ys0), max(ys0)
    xs0 = [q[0] for g in geo for q in g['pts']]; zs0 = [q[2] for g in geo for q in g['pts']]
    cx0, cz0 = (max(xs0) + min(xs0)) / 2, (max(zs0) + min(zs0)) / 2
    r0 = radio * max(max(xs0) - min(xs0), max(zs0) - min(zs0)) / 2
    for g in geo:
        P = g['pts']; nuevo = []
        for k in range(0, len(g['idx']) - 2, 3):
            tri = g['idx'][k:k + 3]
            if corte > 0 and max(P[i][1] for i in tri) < y0 + corte * (y1 - y0): continue
            if radio > 0 and min(math.hypot(P[i][0] - cx0, P[i][2] - cz0) for i in tri) > r0: continue
            nuevo += tri
        usados = sorted(set(nuevo)); mapa = {o: n for n, o in enumerate(usados)}
        g['idx'] = [mapa[i] for i in nuevo]; g['pts'] = [P[i] for i in usados]
        if g['nrm']: g['nrm'] = [g['nrm'][i] for i in usados]
        if g['uv']: g['uv'] = [g['uv'][i] for i in usados]
    geo = [g for g in geo if g['idx']]

# normalización a escala real
xs = [q[0] for g in geo for q in g['pts']]; ys = [q[1] for g in geo for q in g['pts']]; zs = [q[2] for g in geo for q in g['pts']]
ext = max(max(xs) - min(xs), max(zs) - min(zs)); s = ancho / ext
cx, cz, my = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2, min(ys)
for g in geo:
    g['pts'] = [((x - cx) * s, (y - my) * s, (z - cz) * s) for x, y, z in g['pts']]
alto = (max(ys) - my) * s

# texturas
work = dst + '.work'; shutil.rmtree(work, ignore_errors=True); os.makedirs(work + '/tex')
texcache = {}
def texture(ti):
    if ti in texcache: return texcache[ti]
    img = G['images'][G['textures'][ti]['source']]
    if 'bufferView' in img: raw, _ = bview(img['bufferView'])
    else: raw = base64.b64decode(img['uri'].split(',', 1)[1])
    ext = '.png' if raw[:4] == b'\x89PNG' else '.jpg'
    f = f'{work}/tex/t{ti}{ext}'; open(f, 'wb').write(raw)
    subprocess.run(['sips', '-Z', '1024', f], capture_output=True)
    if ext == '.png':  # PNG sin alfa útil -> JPG (más liviano)
        out = f[:-4] + '.jpg'
        subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '82', f, '--out', out], capture_output=True)
        if os.path.exists(out): os.remove(f); f = out
    else:
        subprocess.run(['sips', '-s', 'formatOptions', '82', f], capture_output=True)
    texcache[ti] = './tex/' + os.path.basename(f); return texcache[ti]

L = ['#usda 1.0', '(', '    defaultPrim = "Root"', '    metersPerUnit = 1', '    upAxis = "Y"', ')', 'def Xform "Root"', '{']
def fl(v): return '%.6g' % v
mats = G.get('materials', [])
for mi, mat in enumerate(mats):
    pbr = mat.get('pbrMetallicRoughness', {})
    L.append(f'    def Material "M{mi}"\n    {{\n        token outputs:surface.connect = </Root/M{mi}/S.outputs:surface>')
    L.append(f'        def Shader "uv"\n        {{\n            uniform token info:id = "UsdPrimvarReader_float2"\n            string inputs:varname = "st"\n            float2 outputs:result\n        }}')
    sh = ['        def Shader "S"', '        {', '            uniform token info:id = "UsdPreviewSurface"', '            token outputs:surface']
    bc = pbr.get('baseColorFactor', [1, 1, 1, 1])
    if 'baseColorTexture' in pbr:
        t = texture(pbr['baseColorTexture']['index'])
        L.append(f'        def Shader "base"\n        {{\n            uniform token info:id = "UsdUVTexture"\n            asset inputs:file = @{t}@\n            token inputs:sourceColorSpace = "sRGB"\n            float4 inputs:scale = ({fl(bc[0])}, {fl(bc[1])}, {fl(bc[2])}, 1)\n            float2 inputs:st.connect = </Root/M{mi}/uv.outputs:result>\n            float3 outputs:rgb\n        }}')
        sh.append(f'            color3f inputs:diffuseColor.connect = </Root/M{mi}/base.outputs:rgb>')
    else:
        sh.append(f'            color3f inputs:diffuseColor = ({fl(bc[0])}, {fl(bc[1])}, {fl(bc[2])})')
    if 'metallicRoughnessTexture' in pbr:
        t = texture(pbr['metallicRoughnessTexture']['index'])
        L.append(f'        def Shader "mr"\n        {{\n            uniform token info:id = "UsdUVTexture"\n            asset inputs:file = @{t}@\n            token inputs:sourceColorSpace = "raw"\n            float2 inputs:st.connect = </Root/M{mi}/uv.outputs:result>\n            float outputs:g\n            float outputs:b\n        }}')
        sh.append(f'            float inputs:roughness.connect = </Root/M{mi}/mr.outputs:g>')
        sh.append(f'            float inputs:metallic.connect = </Root/M{mi}/mr.outputs:b>')
    else:
        sh.append(f'            float inputs:roughness = {fl(pbr.get("roughnessFactor", 0.7))}')
        sh.append(f'            float inputs:metallic = {fl(min(pbr.get("metallicFactor", 0.0), 0.2))}')
    if 'normalTexture' in mat:
        t = texture(mat['normalTexture']['index'])
        L.append(f'        def Shader "nor"\n        {{\n            uniform token info:id = "UsdUVTexture"\n            asset inputs:file = @{t}@\n            token inputs:sourceColorSpace = "raw"\n            float4 inputs:scale = (2, 2, 2, 1)\n            float4 inputs:bias = (-1, -1, -1, 0)\n            float2 inputs:st.connect = </Root/M{mi}/uv.outputs:result>\n            float3 outputs:rgb\n        }}')
        sh.append(f'            normal3f inputs:normal.connect = </Root/M{mi}/nor.outputs:rgb>')
    L += sh + ['        }', '    }']

for gi, g in enumerate(geo):
    n3 = len(g['idx']) // 3
    L.append(f'    def Mesh "G{gi}" (\n        prepend apiSchemas = ["MaterialBindingAPI"]\n    )\n    {{')
    L.append('        uniform token subdivisionScheme = "none"')
    L.append('        int[] faceVertexCounts = [' + ','.join(['3'] * n3) + ']')
    L.append('        int[] faceVertexIndices = [' + ','.join(map(str, g['idx'][:n3 * 3])) + ']')
    L.append('        point3f[] points = [' + ','.join(f'({fl(a)},{fl(b)},{fl(c)})' for a, b, c in g['pts']) + ']')
    if g['nrm']:
        L.append('        normal3f[] normals = [' + ','.join(f'({fl(a)},{fl(b)},{fl(c)})' for a, b, c in g['nrm']) + '] (\n            interpolation = "vertex"\n        )')
    if g['uv']:
        L.append('        texCoord2f[] primvars:st = [' + ','.join(f'({fl(a)},{fl(b)})' for a, b in g['uv']) + '] (\n            interpolation = "vertex"\n        )')
    if g['mat'] is not None:
        L.append(f'        rel material:binding = </Root/M{g["mat"]}>')
    L.append('    }')
L.append('}')
open(work + '/m.usda', 'w').write('\n'.join(L))
subprocess.run(['usdcat', work + '/m.usda', '-o', work + '/m.usdc'], check=True)
if os.path.exists(dst): os.remove(dst)
subprocess.run(['usdzip', '-a', 'm.usdc', os.path.abspath(dst)], cwd=work, check=True, capture_output=True)
print(os.path.basename(dst), f'{os.path.getsize(dst)/1e6:.1f} MB', f'alto {alto*100:.1f} cm', 'prims', len(geo), 'mats', len(mats))

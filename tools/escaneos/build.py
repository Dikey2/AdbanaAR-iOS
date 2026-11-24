# Descarga un modelo CC0 de Poly Haven (USD), cambia EXR por JPG, quita MaterialX,
# lo pasa a Y-up y lo empaqueta como USDZ.
import json, sys, os, re, subprocess, urllib.request, shutil
op=urllib.request.build_opener(); op.addheaders=[('User-Agent','asset-fetch/1.0')]; urllib.request.install_opener(op)
aid = sys.argv[1]; res = sys.argv[2] if len(sys.argv) > 2 else '1k'
d = json.load(urllib.request.urlopen(f"https://api.polyhaven.com/files/{aid}"))
u = d['usd'][res]['usd']
w = f"work/{aid}"; shutil.rmtree(w, ignore_errors=True); os.makedirs(f"{w}/textures")
def get(url, path):
    c = f"cache/{os.path.basename(url)}"
    os.makedirs("cache", exist_ok=True)
    if not os.path.exists(c): urllib.request.urlretrieve(url, c)
    shutil.copy(c, path)
get(u['url'], f"{w}/m.usdc")
for rel, v in u.get('include', {}).items():
    url = v['url']
    if rel.endswith('.exr'):
        url = url.replace('/exr/', '/jpg/').replace('.exr', '.jpg'); rel = rel[:-4] + '.jpg'
    get(url, f"{w}/textures/{os.path.basename(rel)}")
s = subprocess.run(['usdcat', f"{w}/m.usdc"], capture_output=True, text=True, check=True).stdout
s = s.replace('.exr@', '.jpg@')
s = re.sub(r'@[^@\n]*?([^\\\\/@]+\.(?:jpg|png))@', r'@./textures/\1@', s)
s = re.sub(r'\n\s*token outputs:mtlx:surface(\.connect)? = [^\n]*', '', s)
def quitar(s):
    # elimina bloques NodeGraph y Shader MaterialX (ND_*), que RealityKit/ARKit no usan
    out=[]; i=0
    pat=re.compile(r'\n(\s*)def (NodeGraph|Shader) "[^"]*"[^\n]*\n\s*\{')
    while True:
        m=pat.search(s,i)
        if not m: out.append(s[i:]); break
        j=m.end(); depth=1
        while depth: 
            if s[j]=='{': depth+=1
            elif s[j]=='}': depth-=1
            j+=1
        bloque=s[m.start():j]
        if m.group(2)=='NodeGraph' or 'info:id = "ND_' in bloque:
            out.append(s[i:m.start()]); i=j
        else:
            out.append(s[i:m.end()]); i=m.end()
    return ''.join(out)
s = quitar(s)
# Algunos modelos conectan el color base a una máscara: se fuerza la textura difusa (sRGB).
difusas = [f for f in os.listdir(f"{w}/textures") if '_diff_' in f]
for m in re.finditer(r'diffuseColor\.connect = <[^>]*/([^/>]+)\.outputs', s):
    nombre = m.group(1)
    b = re.search(r'def Shader "' + nombre + r'"[^{]*\{[^}]*\}', s)
    if b and difusas and '_diff_' not in b.group(0):
        nb = re.sub(r'@\./textures/[^@]+@', '@./textures/' + difusas[0] + '@', b.group(0)).replace('"raw"', '"sRGB"')
        s = s.replace(b.group(0), nb); print('difusa corregida en', nombre)
up = re.search(r'upAxis = "(\w)"', s).group(1)
open(f"{w}/m.usda", 'w').write(s)
rot = 'float xformOp:rotateX = -90\n            uniform token[] xformOpOrder = ["xformOp:rotateX"]' if up == 'Z' else ''
open(f"{w}/{aid}.usda", 'w').write(f'''#usda 1.0
(
    defaultPrim = "Root"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "Root"
{{
    def Xform "escaneo" (
        prepend references = @./m.usda@
    )
    {{
            {rot}
    }}
}}
''')
os.makedirs("out", exist_ok=True)
flat = f"{w}/flat.usdc"
subprocess.run(['usdcat', '--flatten', f"{w}/{aid}.usda", '-o', flat], check=True)
out = os.path.abspath(f"out/{aid}.usdz")
if os.path.exists(out): os.remove(out)
r = subprocess.run(['usdzip', '-a', 'flat.usdc', out], cwd=w, capture_output=True, text=True)
print(aid, up, r.returncode, r.stdout[-400:], r.stderr[-600:], os.path.getsize(out) if os.path.exists(out) else 'NO FILE')

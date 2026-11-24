// Recorta márgenes transparentes y (opcional) quita un fondo de croma magenta. Salida PNG con alfa.
import AppKit
let a = CommandLine.arguments; let inp = a[1], out = a[2], lado = Int(a[3]) ?? 600, croma = a.count > 4
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: inp)))!
let w = src.pixelsWide, h = src.pixelsHigh
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w*4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
src.draw(in: NSRect(x: 0, y: 0, width: w, height: h)); NSGraphicsContext.restoreGraphicsState()
let p = rep.bitmapData!
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
  let i = (y*w + x)*4
  if croma && y < 220 { p[i]=0; p[i+1]=0; p[i+2]=0; p[i+3]=0 }
  else if croma {
    let r = Float(p[i])/255, g = Float(p[i+1])/255, b = Float(p[i+2])/255
    // distancia al magenta puro: cuanto más magenta, más transparente
    let m = min(r, b) - g
    let alfa = max(0, min(1, 1 - (m - 0.25) / 0.45))
    if alfa < 1 {
      // quitar el tinte magenta del borde (despill) y premultiplicar
      let gg = g, rr = min(r, max(gg, r - (1-alfa)*0.8)), bb = min(b, max(gg, b - (1-alfa)*0.8))
      p[i] = UInt8(rr*alfa*255); p[i+1] = UInt8(gg*alfa*255); p[i+2] = UInt8(bb*alfa*255); p[i+3] = UInt8(alfa*255)
    }
  }
  if p[i+3] > 12 { minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y) }
}}
let bw = maxX-minX+1, bh = maxY-minY+1, s = max(bw,bh), pad = s/14, S = s+2*pad
let outRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: lado*4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outRep)
NSGraphicsContext.current!.imageInterpolation = .high
let img = NSImage(size: NSSize(width: w, height: h)); img.addRepresentation(rep)
// el rectángulo fuente está en coordenadas con origen abajo
let ox = minX - pad - (s-bw)/2, oyTop = minY - pad - (s-bh)/2
let srcRect = NSRect(x: ox, y: h - (oyTop + S), width: S, height: S)
img.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado), from: srcRect, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! outRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out, bw, bh)

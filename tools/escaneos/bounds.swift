import ModelIO
for p in CommandLine.arguments.dropFirst() {
  let a = MDLAsset(url: URL(fileURLWithPath: p))
  let b = a.boundingBox
  func f(_ v: SIMD3<Float>) -> String { String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z) }
  print((p as NSString).lastPathComponent, "min", f(b.minBounds), "max", f(b.maxBounds))
}

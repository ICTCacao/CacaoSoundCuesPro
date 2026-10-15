import AppKit
// crop in.png x y w h out.png（左上が原点のピクセル座標）
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!
var rect = NSRect.zero
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let r = CGRect(x: Int(a[2])!, y: Int(a[3])!, width: Int(a[4])!, height: Int(a[5])!)
let out = cg.cropping(to: r)!
let rep = NSBitmapImageRep(cgImage: out)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[6]))
print(a[6], out.width, out.height)

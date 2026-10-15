import CoreGraphics
import Foundation
// 引数のアプリ名のウインドウ番号と枠（x y w h）を出す（前にあるものから）
let name = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == name && (w[kCGWindowLayer as String] as? Int) == 0 {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    print(w[kCGWindowNumber as String]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!), w[kCGWindowName as String] as? String ?? "")
}

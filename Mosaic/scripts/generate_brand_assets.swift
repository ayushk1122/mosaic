import AppKit
import Foundation

let cream = (red: CGFloat(0.965), green: CGFloat(0.949), blue: CGFloat(0.902)) // #F6F2E6
let assets = URL(fileURLWithPath: "/Users/akrishnappa/Developer/mosaic/Mosaic/Mosaic/Assets.xcassets")
let srcM = URL(fileURLWithPath: "/Users/akrishnappa/.cursor/projects/Users-akrishnappa-Developer-mosaic-Mosaic/assets/mosaic_03_m_monogram-58bf6af3-2c56-40ba-b01c-b4d82083c5f2.png")
let srcW = URL(fileURLWithPath: "/Users/akrishnappa/.cursor/projects/Users-akrishnappa-Developer-mosaic-Mosaic/assets/mosaic_03_wordmark-9f6d4a9f-9444-430c-9984-ab49091dc824.png")

func writeImageset(name: String, image: NSImage, filename: String, template: Bool) throws {
    let dir = assets.appendingPathComponent("\(name).imageset")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "brand", code: 1)
    }
    try png.write(to: dir.appendingPathComponent(filename))
    let propertiesBlock = template
        ? """
  ,
  "properties" : {
    "template-rendering-intent" : "template"
  }
"""
        : ""
    let json = """
{
  "images" : [
    {
      "filename" : "\(filename)",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }\(propertiesBlock)
}
"""
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func blackGlyph(from source: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: source),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let provider = cg.dataProvider,
          let data = provider.data,
          let ptr = CFDataGetBytePtr(data)
    else { return nil }

    let width = cg.width
    let height = cg.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let offset = (y * width + x) * bytesPerPixel
            let r = CGFloat(ptr[offset])
            let g = CGFloat(ptr[offset + 1])
            let b = CGFloat(ptr[offset + 2])
            let a = CGFloat(ptr[offset + 3])
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            let i = offset
            if a > 16, luminance > 0.05 {
                buffer[i] = 0
                buffer[i + 1] = 0
                buffer[i + 2] = 0
                buffer[i + 3] = 255
            }
        }
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let out = context.makeImage() else { return nil }
    return NSImage(cgImage: out, size: NSSize(width: width, height: height))
}

func iconImage(monogram: NSImage) -> NSImage {
    let size = 1024
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    NSColor(red: cream.red, green: cream.green, blue: cream.blue, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    let scale = 0.64
    let targetWidth = CGFloat(size) * scale
    let aspect = monogram.size.height / monogram.size.width
    let targetHeight = targetWidth * aspect
    let rect = NSRect(
        x: (CGFloat(size) - targetWidth) / 2,
        y: (CGFloat(size) - targetHeight) / 2,
        width: targetWidth,
        height: targetHeight
    )
    monogram.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    canvas.unlockFocus()
    return canvas
}

guard let monogram = blackGlyph(from: srcM),
      let wordmark = blackGlyph(from: srcW)
else {
    fatalError("glyph extraction failed")
}

try writeImageset(name: "MosaicMonogram", image: monogram, filename: "mosaic-monogram.png", template: true)
try writeImageset(name: "MosaicWordmark", image: wordmark, filename: "mosaic-wordmark.png", template: true)

func resized(_ image: NSImage, maxPixel: CGFloat) -> NSImage {
    let aspect = image.size.width / image.size.height
    let width = aspect >= 1 ? maxPixel : maxPixel * aspect
    let height = aspect >= 1 ? maxPixel / aspect : maxPixel
    let target = NSImage(size: NSSize(width: width, height: height))
    target.lockFocus()
    image.draw(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    target.unlockFocus()
    return target
}

func writeScaledImageset(name: String, image: NSImage, baseName: String, template: Bool) throws {
    let dir = assets.appendingPathComponent("\(name).imageset")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let scales: [(String, CGFloat)] = [("2x", 48), ("3x", 72)]
    var entries: [String] = []
    for (scale, pixels) in scales {
        let filename = "\(baseName)@\(scale).png"
        let scaled = resized(image, maxPixel: pixels)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { throw NSError(domain: "brand", code: 2) }
        try png.write(to: dir.appendingPathComponent(filename))
        entries.append("""
    {
      "filename" : "\(filename)",
      "idiom" : "universal",
      "scale" : "\(scale)"
    }
""")
    }

    let propertiesBlock = template
        ? """
  ,
  "properties" : {
    "template-rendering-intent" : "template"
  }
"""
        : ""
    let json = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }\(propertiesBlock)
}
"""
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

try writeScaledImageset(name: "MosaicMonogramTab", image: monogram, baseName: "mosaic-monogram-tab", template: true)

let icon = iconImage(monogram: monogram)
guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("icon png") }
try png.write(to: assets.appendingPathComponent("AppIcon.appiconset/AppIcon-1024.png"))
print("done")

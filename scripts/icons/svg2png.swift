// svg2png.swift — rasterize an SVG to a PNG or TIFF at an exact pixel size.
//
// Used by build-icons.sh (issue #25) instead of a third-party SVG
// rasterizer: AppKit's NSImage has decoded SVG via ImageIO since macOS 11,
// so this needs nothing beyond the Swift toolchain already required to
// build Nagi itself.
//
// Usage: swift svg2png.swift <in.svg> <out.png|out.tiff> <pixelSize>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let px = Double(args[3]), px > 0 else {
    FileHandle.standardError.write(
        Data("usage: svg2png.swift <in.svg> <out.png|out.tiff> <pixelSize>\n".utf8))
    exit(64)
}
let inPath = args[1]
let outPath = args[2]

guard let image = NSImage(contentsOfFile: inPath) else {
    FileHandle.standardError.write(Data("error: failed to load SVG at \(inPath)\n".utf8))
    exit(1)
}

let size = NSSize(width: px, height: px)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(px), pixelsHigh: Int(px),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("error: could not create bitmap rep\n".utf8))
    exit(1)
}
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

let isTIFF = outPath.lowercased().hasSuffix(".tiff") || outPath.lowercased().hasSuffix(".tif")
let data: Data?
if isTIFF {
    data = rep.tiffRepresentation
} else {
    data = rep.representation(using: .png, properties: [:])
}
guard let outData = data else {
    FileHandle.standardError.write(Data("error: failed to encode output\n".utf8))
    exit(1)
}
do {
    try outData.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outPath): \(error)\n".utf8))
    exit(1)
}
print("wrote \(outPath) (\(Int(px)) x\(Int(px)))")

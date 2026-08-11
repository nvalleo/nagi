// svg2pdf.swift — render an SVG into a single-page PDF at an exact point
// size (#30 follow-up icon fix — see build-icons.sh).
//
// Companion to svg2png.swift, same AppKit-SVG-decoder approach, but
// drawing into a CGContext-backed PDF page instead of a bitmap: needed
// for TISIconLabels > CustomIcon (the glyph System Settings' Input
// Sources list actually uses — see generate.py's template_icon_svg()
// docstring for why this exists at all).
//
// Usage: swift svg2pdf.swift <in.svg> <out.pdf> <pointSize>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let pt = Double(args[3]), pt > 0 else {
    FileHandle.standardError.write(Data("usage: svg2pdf.swift <in.svg> <out.pdf> <pointSize>\n".utf8))
    exit(64)
}
let inPath = args[1]
let outPath = args[2]

guard let image = NSImage(contentsOfFile: inPath) else {
    FileHandle.standardError.write(Data("error: failed to load SVG at \(inPath)\n".utf8))
    exit(1)
}

var mediaBox = CGRect(x: 0, y: 0, width: pt, height: pt)
guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: outPath) as CFURL),
    let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
else {
    FileHandle.standardError.write(Data("error: could not create PDF context\n".utf8))
    exit(1)
}

pdfContext.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: pdfContext, flipped: false)
image.draw(
    in: CGRect(x: 0, y: 0, width: pt, height: pt), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()
pdfContext.endPDFPage()
pdfContext.closePDF()

print("wrote \(outPath) (\(pt) pt)")

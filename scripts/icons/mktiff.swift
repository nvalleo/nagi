// mktiff.swift — combine a 1x and 2x TIFF into a single multi-representation
// TIFF, correctly tagged as HiDPI (issue #35 follow-up).
//
// `tiffutil -cathidpicheck` (used here previously) concatenates two TIFFs
// into one file, but only *validates* that the 2x image is exactly double
// the 1x image's pixel size — it doesn't write HiDPI resolution metadata
// into the output. Both representations end up tagged 72 dpi, so a
// consumer reading the file's own metadata sees two representations that
// each claim to be a plain 1x image at two different point sizes (16pt
// and 32pt), not a 1x/2x pair of the same 16pt icon — confirmed against
// AinuIM.app's own Ainu.tiff, whose 2x representation is tagged 144 dpi
// (`NSBitmapImageRep.size` in *points*, not pixels, is what actually
// carries this: setting it to the intended point size on a rep with
// double the pixel dimensions is what produces the higher dpi tag).
//
// Usage: swift mktiff.swift <out.tiff> <pointSize> <1x.tiff> <2x.tiff>
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let pt = Double(args[2]), pt > 0 else {
    FileHandle.standardError.write(
        Data("usage: mktiff.swift <out.tiff> <pointSize> <1x.tiff> <2x.tiff>\n".utf8))
    exit(64)
}
let outPath = args[1]
let inPaths = [args[3], args[4]]

var reps: [NSImageRep] = []
for path in inPaths {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let rep = NSBitmapImageRep(data: data)
    else {
        FileHandle.standardError.write(Data("error: failed to load \(path)\n".utf8))
        exit(1)
    }
    // Points, not pixels — this is what tags a rep as HiDPI (a rep whose
    // pixel size is larger than this point size becomes the 2x variant).
    rep.size = NSSize(width: pt, height: pt)
    reps.append(rep)
}

guard let outData = NSBitmapImageRep.representationOfImageReps(in: reps, using: .tiff, properties: [:])
else {
    FileHandle.standardError.write(Data("error: failed to combine representations\n".utf8))
    exit(1)
}
do {
    try outData.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outPath): \(error)\n".utf8))
    exit(1)
}
print("wrote \(outPath) (\(reps.count) representations, \(Int(pt)) pt)")

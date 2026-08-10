"""wave.py — smooth SVG path generation for the "calming wave" mark used in
Nagi's app icon and mode/menu-bar badge (see generate.py, issue #25).

A wave is sampled as a plain sine and then fit through a Catmull-Rom ->
cubic Bezier conversion, which is what keeps it reading as one fluid brush
stroke instead of a faceted polyline. `periods` should be a multiple of 0.5
so both endpoints land on the centerline on their own (sin(k*pi) == 0) —
that's what lets a stroke's rounded cap sit flush on the baseline without
any extra tapering logic.
"""
import math


def catmull_rom_to_bezier(points):
    """Convert a list of (x, y) points into an SVG path 'd' string (M + C...)
    passing through every point, using Catmull-Rom -> cubic Bezier control
    points (uniform, tension 0)."""
    if len(points) < 2:
        raise ValueError("need at least 2 points")
    d = [f"M {points[0][0]:.2f} {points[0][1]:.2f}"]
    n = len(points)
    for i in range(n - 1):
        p0 = points[i - 1] if i - 1 >= 0 else points[i]
        p1 = points[i]
        p2 = points[i + 1]
        p3 = points[i + 2] if i + 2 < n else p2
        c1x = p1[0] + (p2[0] - p0[0]) / 6.0
        c1y = p1[1] + (p2[1] - p0[1]) / 6.0
        c2x = p2[0] - (p3[0] - p1[0]) / 6.0
        c2y = p2[1] - (p3[1] - p1[1]) / 6.0
        d.append(
            f"C {c1x:.2f} {c1y:.2f}, {c2x:.2f} {c2y:.2f}, {p2[0]:.2f} {p2[1]:.2f}"
        )
    return " ".join(d)


def wave_path(cx, cy, width, amplitude, periods, samples=48, phase=0.0):
    """A horizontal wave centered at (cx, cy), spanning `width`, with
    `periods` full sine cycles and given `amplitude`."""
    pts = []
    x0 = cx - width / 2
    for i in range(samples + 1):
        t = i / samples  # 0..1
        x = x0 + t * width
        y = cy + amplitude * math.sin(2 * math.pi * periods * t + phase)
        pts.append((x, y))
    return catmull_rom_to_bezier(pts)

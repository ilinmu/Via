// Package tray renders Option 1 status tray icons using each OS's native system
// Wi-Fi icon plus a subtle P/B corner badge or paused red dot.
package tray

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"

	"via/internal/nativewifi"
	"via/internal/policy"
)

// Badge returns "P", "B", or "" for the active role when running.
func Badge(running bool, role policy.Role) string {
	if !running {
		return ""
	}
	switch role {
	case policy.RolePriority:
		return "P"
	case policy.RoleBackup:
		return "B"
	default:
		return ""
	}
}

// Render returns PNG bytes using the host OS native Wi-Fi icon when available,
// falling back to the cross-platform pure-Go renderer when unavailable.
func Render(ctrl nativewifi.Controller, running bool, role policy.Role, darkBar bool) []byte {
	if data := renderNative(ctrl, running, role, darkBar); len(data) > 0 {
		return data
	}
	return RenderFallback(running, role, darkBar)
}

// RenderFallback draws a crisp 36px-tall @2x PNG matching Option 1.
func RenderFallback(running bool, role policy.Role, darkBar bool) []byte {
	badge := Badge(running, role)
	w := 36
	if badge != "" {
		w = 48
	}
	const h = 36
	img := image.NewNRGBA(image.Rect(0, 0, w, h))

	ink := color.NRGBA{R: 15, G: 23, B: 42, A: 255}
	if darkBar {
		ink = color.NRGBA{R: 255, G: 255, B: 255, A: 255}
	}

	cx, cy := 18.0, 26.0
	if badge != "" {
		cx = 16.0
	}
	for y := 0; y < h; y++ {
		for x := 0; x < 35; x++ {
			dx := float64(x) - cx
			dy := float64(y) - cy
			dist := math.Hypot(dx, dy)

			if dist <= 2.3 {
				alpha := clamp01(2.3 - dist + 0.5)
				blendPixel(img, x, y, ink, alpha)
				continue
			}
			if dy >= 0 || math.Abs(dx) > -dy*1.05 {
				continue
			}
			for _, radius := range []float64{6.5, 11.5, 16.5} {
				halfThick := 1.35
				delta := math.Abs(dist - radius)
				if delta <= halfThick+0.6 {
					alpha := clamp01((halfThick + 0.6 - delta) / 0.85)
					blendPixel(img, x, y, ink, alpha)
				}
			}
		}
	}

	if !running {
		drawRedDotWithHalo(img, 28.5, 25.5, 4.2, 1.4, darkBar)
	} else if badge == "P" {
		drawGlyph2x(img, glyphP, 34, 19, ink)
	} else if badge == "B" {
		drawGlyph2x(img, glyphB, 34, 19, ink)
	}

	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func drawRedDotWithHalo(img *image.NRGBA, rx, ry, r, halo float64, darkBar bool) {
	red := color.NRGBA{R: 239, G: 68, B: 68, A: 255}
	if darkBar {
		red = color.NRGBA{R: 248, G: 113, B: 113, A: 255}
	}
	b := img.Bounds()
	outer := r + halo
	for y := int(math.Floor(ry - outer - 1)); y <= int(math.Ceil(ry + outer + 1)); y++ {
		for x := int(math.Floor(rx - outer - 1)); x <= int(math.Ceil(rx + outer + 1)); x++ {
			if x < b.Min.X || x >= b.Max.X || y < b.Min.Y || y >= b.Max.Y {
				continue
			}
			d := math.Hypot(float64(x)-rx, float64(y)-ry)
			if d <= r+0.6 {
				alpha := clamp01((r + 0.6 - d) / 0.8)
				img.SetNRGBA(x, y, color.NRGBA{R: red.R, G: red.G, B: red.B, A: uint8(math.Round(float64(red.A) * alpha))})
			} else if d <= outer {
				cur := img.NRGBAAt(x, y)
				if cur.A > 0 {
					keep := clamp01((d - r) / halo)
					cur.A = uint8(math.Round(float64(cur.A) * keep))
					img.SetNRGBA(x, y, cur)
				}
			}
		}
	}
}

var glyphP = []string{
	"#### ",
	"#   #",
	"#   #",
	"#### ",
	"#    ",
	"#    ",
	"#    ",
}

var glyphB = []string{
	"#### ",
	"#   #",
	"#   #",
	"#### ",
	"#   #",
	"#   #",
	"#### ",
}

func drawGlyph2x(img *image.NRGBA, rows []string, ox, oy int, c color.NRGBA) {
	b := img.Bounds()
	for ry, row := range rows {
		for rx, ch := range row {
			if ch != '#' {
				continue
			}
			for dy := 0; dy < 2; dy++ {
				for dx := 0; dx < 2; dx++ {
					px := ox + rx*2 + dx
					py := oy + ry*2 + dy
					if px >= b.Min.X && px < b.Max.X && py >= b.Min.Y && py < b.Max.Y {
						img.SetNRGBA(px, py, c)
					}
				}
			}
		}
	}
}

func blendPixel(img *image.NRGBA, x, y int, c color.NRGBA, alpha float64) {
	if alpha <= 0 {
		return
	}
	if alpha > 1 {
		alpha = 1
	}
	cur := img.NRGBAAt(x, y)
	na := uint8(math.Round(float64(c.A) * alpha))
	if na > cur.A {
		img.SetNRGBA(x, y, color.NRGBA{R: c.R, G: c.G, B: c.B, A: na})
	}
}

func clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

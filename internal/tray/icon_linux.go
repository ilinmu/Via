//go:build linux && !android

package tray

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"

	"via/internal/nativewifi"
	"via/internal/policy"
)

func findSystemWifiPNG() image.Image {
	themes := []string{
		"/usr/share/icons/Adwaita",
		"/usr/share/icons/Yaru",
		"/usr/share/icons/breeze",
		"/usr/share/icons/Papirus",
		"/usr/share/icons/hicolor",
	}
	sizes := []string{"32x32", "24x24", "48x48", "16x16", "32", "24", "48"}
	names := []string{
		"network-wireless-signal-excellent-symbolic.png",
		"network-wireless-signal-excellent.png",
		"network-wireless.png",
	}
	for _, theme := range themes {
		for _, sz := range sizes {
			for _, name := range names {
				for _, candidate := range []string{
					filepath.Join(theme, sz, "status", name),
					filepath.Join(theme, "status", sz, name),
				} {
					f, err := os.Open(candidate)
					if err != nil {
						continue
					}
					img, err := png.Decode(f)
					_ = f.Close()
					if err == nil {
						return img
					}
				}
			}
		}
	}
	return nil
}

func renderNative(_ nativewifi.Controller, running bool, role policy.Role, darkBar bool) []byte {
	src := findSystemWifiPNG()
	if src == nil {
		return nil
	}

	badge := Badge(running, role)
	w := 36
	if badge != "" {
		w = 48
	}
	const h = 36
	dst := image.NewNRGBA(image.Rect(0, 0, w, h))

	ink := color.NRGBA{R: 15, G: 23, B: 42, A: 255}
	if darkBar {
		ink = color.NRGBA{R: 255, G: 255, B: 255, A: 255}
	}

	sb := src.Bounds()
	sw, sh := sb.Dx(), sb.Dy()
	if sw <= 0 || sh <= 0 {
		return nil
	}

	iconSize, ox, oy := 28.0, 4.0, 4.0
	if badge != "" {
		iconSize, ox, oy = 26.0, 3.0, 5.0
	}

	for y := 0; y < int(iconSize); y++ {
		sy := sb.Min.Y + int(math.Floor((float64(y)+0.5)*float64(sh)/iconSize))
		if sy >= sb.Max.Y {
			sy = sb.Max.Y - 1
		}
		for x := 0; x < int(iconSize); x++ {
			sx := sb.Min.X + int(math.Floor((float64(x)+0.5)*float64(sw)/iconSize))
			if sx >= sb.Max.X {
				sx = sb.Max.X - 1
			}
			_, _, _, a := src.At(sx, sy).RGBA()
			alpha := uint8(a >> 8)
			if alpha == 0 {
				continue
			}
			dst.SetNRGBA(int(ox)+x, int(oy)+y, color.NRGBA{R: ink.R, G: ink.G, B: ink.B, A: alpha})
		}
	}

	if !running {
		drawRedDotWithHalo(dst, 28.5, 25.5, 4.2, 1.4, darkBar)
	} else if badge == "P" {
		drawGlyph2x(dst, glyphP, 34, 19, ink)
	} else if badge == "B" {
		drawGlyph2x(dst, glyphB, 34, 19, ink)
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, dst); err != nil {
		return nil
	}
	return buf.Bytes()
}

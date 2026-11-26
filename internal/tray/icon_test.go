package tray

import (
	"bytes"
	"image/png"
	"testing"

	"via/internal/policy"
)

func TestRenderTrayIconStatusBadges(t *testing.T) {
	hasRedPixel := func(pngBytes []byte) bool {
		img, err := png.Decode(bytes.NewReader(pngBytes))
		if err != nil {
			t.Fatalf("decode png: %v", err)
		}
		b := img.Bounds()
		for y := b.Min.Y; y < b.Max.Y; y++ {
			for x := b.Min.X; x < b.Max.X; x++ {
				r, g, bl, a := img.At(x, y).RGBA()
				if a > 0 && r > g*2 && r > bl*2 {
					return true
				}
			}
		}
		return false
	}

	hasRightGlyph := func(pngBytes []byte) bool {
		img, err := png.Decode(bytes.NewReader(pngBytes))
		if err != nil {
			t.Fatalf("decode png: %v", err)
		}
		for y := 18; y < 35; y++ {
			for x := 34; x < 46; x++ {
				_, _, _, a := img.At(x, y).RGBA()
				if a > 0 {
					return true
				}
			}
		}
		return false
	}

	pIcon := Render(nil, true, policy.RolePriority, false)
	if hasRedPixel(pIcon) {
		t.Fatal("running priority icon should not have red dot")
	}
	if !hasRightGlyph(pIcon) {
		t.Fatal("running priority icon should draw P glyph")
	}

	bIcon := Render(nil, true, policy.RoleBackup, true)
	if hasRedPixel(bIcon) {
		t.Fatal("running backup icon should not have red dot")
	}
	if !hasRightGlyph(bIcon) {
		t.Fatal("running backup icon should draw B glyph")
	}

	otherIcon := Render(nil, true, policy.RoleOther, false)
	if hasRedPixel(otherIcon) {
		t.Fatal("running outside P/B should not have red dot")
	}
	if hasRightGlyph(otherIcon) {
		t.Fatal("running outside P/B should not draw P/B glyph")
	}

	pausedIcon := Render(nil, false, policy.RolePriority, false)
	if !hasRedPixel(pausedIcon) {
		t.Fatal("paused icon must draw red dot")
	}
	if hasRightGlyph(pausedIcon) {
		t.Fatal("paused icon should not draw P/B glyph")
	}
}

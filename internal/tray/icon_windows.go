//go:build windows

package tray

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"sync"
	"syscall"
	"unsafe"

	"via/internal/nativewifi"
	"via/internal/policy"
)

var (
	gdipDLL     = syscall.NewLazyDLL("gdiplus.dll")
	kernel32DLL = syscall.NewLazyDLL("kernel32.dll")

	procRtlMoveMemory = kernel32DLL.NewProc("RtlMoveMemory")

	procGdiplusStartup               = gdipDLL.NewProc("GdiplusStartup")
	procGdipCreateBitmapFromScan0    = gdipDLL.NewProc("GdipCreateBitmapFromScan0")
	procGdipDisposeImage             = gdipDLL.NewProc("GdipDisposeImage")
	procGdipGetImageGraphicsContext  = gdipDLL.NewProc("GdipGetImageGraphicsContext")
	procGdipDeleteGraphics           = gdipDLL.NewProc("GdipDeleteGraphics")
	procGdipGetDC                    = gdipDLL.NewProc("GdipGetDC")
	procGdipReleaseDC                = gdipDLL.NewProc("GdipReleaseDC")
	procGdipSetSmoothingMode         = gdipDLL.NewProc("GdipSetSmoothingMode")
	procGdipSetTextRenderingHint     = gdipDLL.NewProc("GdipSetTextRenderingHint")
	procGdipSetCompositingMode       = gdipDLL.NewProc("GdipSetCompositingMode")
	procGdipCreateFontFamilyFromName = gdipDLL.NewProc("GdipCreateFontFamilyFromName")
	procGdipDeleteFontFamily         = gdipDLL.NewProc("GdipDeleteFontFamily")
	procGdipCreateFontFromLogfontW   = gdipDLL.NewProc("GdipCreateFontFromLogfontW")
	procGdipDeleteFont               = gdipDLL.NewProc("GdipDeleteFont")
	procGdipCreateSolidFill          = gdipDLL.NewProc("GdipCreateSolidFill")
	procGdipDeleteBrush              = gdipDLL.NewProc("GdipDeleteBrush")
	procGdipCreateStringFormat       = gdipDLL.NewProc("GdipCreateStringFormat")
	procGdipSetStringFormatAlign     = gdipDLL.NewProc("GdipSetStringFormatAlign")
	procGdipSetStringFormatLineAlign = gdipDLL.NewProc("GdipSetStringFormatLineAlign")
	procGdipDeleteStringFormat       = gdipDLL.NewProc("GdipDeleteStringFormat")
	procGdipDrawString               = gdipDLL.NewProc("GdipDrawString")
	procGdipFillEllipseI             = gdipDLL.NewProc("GdipFillEllipseI")
	procGdipBitmapLockBits           = gdipDLL.NewProc("GdipBitmapLockBits")
	procGdipBitmapUnlockBits         = gdipDLL.NewProc("GdipBitmapUnlockBits")

	gdipOnce sync.Once
	gdipOK   bool
)

type gdiplusStartupInput struct {
	GdiplusVersion           uint32
	DebugEventCallback       uintptr
	SuppressBackgroundThread int32
	SuppressExternalCodecs   int32
}

type gdipRectF struct {
	X, Y, Width, Height float32
}

type gdipRectI struct {
	X, Y, Width, Height int32
}

type gdipBitmapData struct {
	Width       uint32
	Height      uint32
	Stride      int32
	PixelFormat int32
	Scan0       uintptr
	Reserved    uintptr
}

type logfontW struct {
	Height         int32
	Width          int32
	Escapement     int32
	Orientation    int32
	Weight         int32
	Italic         byte
	Underline      byte
	StrikeOut      byte
	CharSet        byte
	OutPrecision   byte
	ClipPrecision  byte
	Quality        byte
	PitchAndFamily byte
	FaceName       [32]uint16
}

func ensureGdiplus() bool {
	gdipOnce.Do(func() {
		if err := gdipDLL.Load(); err != nil {
			return
		}
		var token uintptr
		in := gdiplusStartupInput{GdiplusVersion: 1}
		r, _, _ := procGdiplusStartup.Call(uintptr(unsafe.Pointer(&token)), uintptr(unsafe.Pointer(&in)), 0)
		gdipOK = r == 0
	})
	return gdipOK
}

func pickWindowsWifiFontFamily() string {
	for _, name := range []string{"Segoe Fluent Icons", "Segoe MDL2 Assets"} {
		u16, err := syscall.UTF16PtrFromString(name)
		if err != nil {
			continue
		}
		var fam uintptr
		if r, _, _ := procGdipCreateFontFamilyFromName.Call(uintptr(unsafe.Pointer(u16)), 0, uintptr(unsafe.Pointer(&fam))); r == 0 && fam != 0 {
			procGdipDeleteFontFamily.Call(fam)
			return name
		}
	}
	return ""
}

func makeLogfont(face string, pixelHeight, weight int32) logfontW {
	lf := logfontW{
		Height:  -pixelHeight,
		Weight:  weight,
		CharSet: 1,
		Quality: 4,
	}
	if u16, err := syscall.UTF16FromString(face); err == nil {
		copy(lf.FaceName[:], u16)
	}
	return lf
}

func renderNative(_ nativewifi.Controller, running bool, role policy.Role, darkBar bool) []byte {
	if !ensureGdiplus() {
		return nil
	}
	wifiFontName := pickWindowsWifiFontFamily()
	if wifiFontName == "" {
		return nil
	}

	const size = int32(64)
	const pixelFormat32bppARGB = int32(0x0026200A)

	var bmp uintptr
	if r, _, _ := procGdipCreateBitmapFromScan0.Call(
		uintptr(size), uintptr(size), 0, uintptr(pixelFormat32bppARGB), 0, uintptr(unsafe.Pointer(&bmp)),
	); r != 0 || bmp == 0 {
		return nil
	}
	defer procGdipDisposeImage.Call(bmp)

	var gfx uintptr
	if r, _, _ := procGdipGetImageGraphicsContext.Call(bmp, uintptr(unsafe.Pointer(&gfx))); r != 0 || gfx == 0 {
		return nil
	}
	defer procGdipDeleteGraphics.Call(gfx)

	procGdipSetSmoothingMode.Call(gfx, 4)
	procGdipSetTextRenderingHint.Call(gfx, 4)

	var hdc uintptr
	if r, _, _ := procGdipGetDC.Call(gfx, uintptr(unsafe.Pointer(&hdc))); r != 0 || hdc == 0 {
		return nil
	}

	var inkARGB uint32 = 0xFF141414
	if !running && darkBar {
		inkARGB = 0xFFFFFFFF
	}
	var inkBrush uintptr
	if r, _, _ := procGdipCreateSolidFill.Call(uintptr(inkARGB), uintptr(unsafe.Pointer(&inkBrush))); r != 0 || inkBrush == 0 {
		procGdipReleaseDC.Call(gfx, hdc)
		return nil
	}
	defer procGdipDeleteBrush.Call(inkBrush)

	var strFmt uintptr
	if r, _, _ := procGdipCreateStringFormat.Call(0, 0, uintptr(unsafe.Pointer(&strFmt))); r == 0 && strFmt != 0 {
		procGdipSetStringFormatAlign.Call(strFmt, 1)
		procGdipSetStringFormatLineAlign.Call(strFmt, 1)
		defer procGdipDeleteStringFormat.Call(strFmt)
	}

	badge := Badge(running, role)
	wifiSize := int32(44)
	wifiRect := gdipRectF{X: 0, Y: 0, Width: 64, Height: 64}
	if badge != "" {
		wifiSize = 38
		wifiRect = gdipRectF{X: 2, Y: 6, Width: 42, Height: 42}
	} else if !running {
		wifiSize = 42
		wifiRect = gdipRectF{X: 4, Y: 6, Width: 48, Height: 48}
	}

	wifiLF := makeLogfont(wifiFontName, wifiSize, 400)
	var wifiFont uintptr
	if r, _, _ := procGdipCreateFontFromLogfontW.Call(hdc, uintptr(unsafe.Pointer(&wifiLF)), uintptr(unsafe.Pointer(&wifiFont))); r != 0 || wifiFont == 0 {
		procGdipReleaseDC.Call(gfx, hdc)
		return nil
	}

	var badgeFont uintptr
	if badge != "" {
		badgeLF := makeLogfont("Segoe UI", 22, 700)
		procGdipCreateFontFromLogfontW.Call(hdc, uintptr(unsafe.Pointer(&badgeLF)), uintptr(unsafe.Pointer(&badgeFont)))
	}
	procGdipReleaseDC.Call(gfx, hdc)

	defer procGdipDeleteFont.Call(wifiFont)
	if badgeFont != 0 {
		defer procGdipDeleteFont.Call(badgeFont)
	}

	wifiGlyph, _ := syscall.UTF16PtrFromString("\uE701")
	procGdipDrawString.Call(gfx, uintptr(unsafe.Pointer(wifiGlyph)), 1, wifiFont, uintptr(unsafe.Pointer(&wifiRect)), strFmt, inkBrush)

	if badge != "" && badgeFont != 0 {
		badgePtr, _ := syscall.UTF16PtrFromString(badge)
		badgeRect := gdipRectF{X: 36, Y: 30, Width: 26, Height: 30}
		procGdipDrawString.Call(gfx, uintptr(unsafe.Pointer(badgePtr)), 1, badgeFont, uintptr(unsafe.Pointer(&badgeRect)), strFmt, inkBrush)
	} else if !running {
		var clearBrush, redBrush uintptr
		procGdipCreateSolidFill.Call(0x00000000, uintptr(unsafe.Pointer(&clearBrush)))
		redColor := uint32(0xFFEF4444)
		if darkBar {
			redColor = 0xFFF87171
		}
		procGdipCreateSolidFill.Call(uintptr(redColor), uintptr(unsafe.Pointer(&redBrush)))
		if clearBrush != 0 {
			procGdipSetCompositingMode.Call(gfx, 1)
			procGdipFillEllipseI.Call(gfx, clearBrush, 41, 39, 22, 22)
			procGdipDeleteBrush.Call(clearBrush)
		}
		if redBrush != 0 {
			procGdipSetCompositingMode.Call(gfx, 0)
			procGdipFillEllipseI.Call(gfx, redBrush, 44, 42, 16, 16)
			procGdipDeleteBrush.Call(redBrush)
		}
	}

	lockRect := gdipRectI{X: 0, Y: 0, Width: size, Height: size}
	var bd gdipBitmapData
	if r, _, _ := procGdipBitmapLockBits.Call(bmp, uintptr(unsafe.Pointer(&lockRect)), 1, uintptr(pixelFormat32bppARGB), uintptr(unsafe.Pointer(&bd))); r != 0 || bd.Scan0 == 0 {
		return nil
	}
	defer procGdipBitmapUnlockBits.Call(bmp, uintptr(unsafe.Pointer(&bd)))

	out := image.NewNRGBA(image.Rect(0, 0, int(size), int(size)))
	row := make([]byte, int(size)*4)
	for y := 0; y < int(size); y++ {
		procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&row[0])), bd.Scan0+uintptr(y)*uintptr(bd.Stride), uintptr(len(row)))
		for x := 0; x < int(size); x++ {
			off := x * 4
			out.SetNRGBA(x, y, color.NRGBA{R: row[off+2], G: row[off+1], B: row[off], A: row[off+3]})
		}
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, out); err != nil {
		return nil
	}
	return buf.Bytes()
}

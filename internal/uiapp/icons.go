package uiapp

import "github.com/egoist/mygo/ui"

var (
	svgChevronDown = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>`))
	svgChevronUp   = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg>`))
	svgLock        = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>`))
	svgEye         = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6z"/><circle cx="12" cy="12" r="2.8"/></svg>`))
	svgEyeOff      = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.94 10.94 0 0 1 12 18c-6.5 0-10-6-10-6a18.5 18.5 0 0 1 5.06-5.94"/><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c6.5 0 10 6 10 6a18.5 18.5 0 0 1-2.16 3.19"/><path d="M14.12 14.12a3 3 0 0 1-4.24-4.24"/><path d="M2 2l20 20"/></svg>`))

	// Three-level monochrome Wi-Fi signal strength icons.
	svgSignalStrong = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M3 8.5a13 13 0 0 1 18 0"/><path d="M6.5 12a8.2 8.2 0 0 1 11 0"/><path d="M10 15.5a3.5 3.5 0 0 1 4 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor" stroke="none"/></svg>`))
	svgSignalMedium = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M3 8.5a13 13 0 0 1 18 0" stroke-opacity="0.25"/><path d="M6.5 12a8.2 8.2 0 0 1 11 0"/><path d="M10 15.5a3.5 3.5 0 0 1 4 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor" stroke="none"/></svg>`))
	svgSignalWeak   = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M3 8.5a13 13 0 0 1 18 0" stroke-opacity="0.25"/><path d="M6.5 12a8.2 8.2 0 0 1 11 0" stroke-opacity="0.25"/><path d="M10 15.5a3.5 3.5 0 0 1 4 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor" stroke="none"/></svg>`))

	// Scheme C header brand mark ("Deep Space Route V") layers.
	svgBrandRight = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"><path d="M18.2 7.2L12.6 15.8"/></svg>`))
	svgBrandLeft  = ui.MustParseSVG([]byte(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5.8 7.2L12 16.8"/><circle cx="12" cy="6.6" r="1.6" fill="currentColor" stroke="none"/></svg>`))
)

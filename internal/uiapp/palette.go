package uiapp

import "github.com/egoist/mygo/ui"

type palette struct {
	dark         bool
	bg           ui.Color
	surface      ui.Color
	surfaceMuted ui.Color
	border       ui.Color
	text         ui.Color
	muted        ui.Color
	accent       ui.Color
	accentSoft   ui.Color
	accentText   ui.Color
	success      ui.Color
	successSoft  ui.Color
	successText  ui.Color
	warning      ui.Color
	warningSoft  ui.Color
	warningText  ui.Color
	danger       ui.Color
	dangerSoft   ui.Color
	dangerText   ui.Color
}

func schemeAPalette(dark bool) palette {
	if dark {
		return palette{
			dark:         true,
			bg:           ui.Hex("#0B1120"),
			surface:      ui.Hex("#141D30"),
			surfaceMuted: ui.Hex("#1E293B"),
			border:       ui.Hex("#263449"),
			text:         ui.Hex("#F8FAFC"),
			muted:        ui.Hex("#94A3B8"),
			accent:       ui.Hex("#3B82F6"),
			accentSoft:   ui.RGBA(59, 130, 246, 0.18),
			accentText:   ui.Hex("#93C5FD"),
			success:      ui.Hex("#34D399"),
			successSoft:  ui.RGBA(52, 211, 153, 0.16),
			successText:  ui.Hex("#6EE7B7"),
			warning:      ui.Hex("#FBBF24"),
			warningSoft:  ui.RGBA(251, 191, 36, 0.16),
			warningText:  ui.Hex("#FDE68A"),
			danger:       ui.Hex("#F87171"),
			dangerSoft:   ui.RGBA(248, 113, 113, 0.16),
			dangerText:   ui.Hex("#FCA5A5"),
		}
	}
	return palette{
		dark:         false,
		bg:           ui.Hex("#F4F7FB"),
		surface:      ui.Hex("#FFFFFF"),
		surfaceMuted: ui.Hex("#EAF0F8"),
		border:       ui.Hex("#E2E8F0"),
		text:         ui.Hex("#0F172A"),
		muted:        ui.Hex("#64748B"),
		accent:       ui.Hex("#2563EB"),
		accentSoft:   ui.RGBA(37, 99, 235, 0.10),
		accentText:   ui.Hex("#1D4ED8"),
		success:      ui.Hex("#10B981"),
		successSoft:  ui.RGBA(16, 185, 129, 0.12),
		successText:  ui.Hex("#047857"),
		warning:      ui.Hex("#F59E0B"),
		warningSoft:  ui.RGBA(245, 158, 11, 0.14),
		warningText:  ui.Hex("#B45309"),
		danger:       ui.Hex("#EF4444"),
		dangerSoft:   ui.RGBA(239, 68, 68, 0.12),
		dangerText:   ui.Hex("#B91C1C"),
	}
}

func applyTheme(c *ui.Context, p palette) {
	t := *c.Theme()
	t.Dark = p.dark
	t.Background = p.bg
	t.Surface = p.surface
	t.SurfaceHover = p.surfaceMuted
	t.SurfacePressed = p.surfaceMuted
	t.Border = p.border
	t.Text = p.text
	t.TextMuted = p.muted
	t.Accent = p.accent
	t.AccentHover = p.accent
	t.AccentPressed = p.accent
	t.InactiveAccent = p.accent
	t.Success = p.success
	t.Warning = p.warning
	t.Danger = p.danger
	c.SetTheme(&t)
}

package i18n

import (
	"reflect"
	"strings"
	"testing"
)

func TestCatalogCompletenessAndStyleInvariants(t *testing.T) {
	checkValue := func(lang Lang, name, val string) {
		t.Helper()
		if strings.TrimSpace(val) == "" {
			t.Fatalf("%s field %s is empty", lang, name)
		}
		if strings.Contains(val, "·") {
			t.Fatalf("%s field %s contains disallowed middle dot: %q", lang, name, val)
		}
		if strings.Contains(val, "SSID") {
			t.Fatalf("%s field %s exposes technical term SSID: %q", lang, name, val)
		}
		if strings.Contains(val, "立即") {
			t.Fatalf("%s field %s uses pushy wording 立即: %q", lang, name, val)
		}
		if strings.Contains(val, "Now") {
			t.Fatalf("%s field %s uses pushy wording Now: %q", lang, name, val)
		}
	}

	for _, lang := range []Lang{LangZH, LangEN} {
		s := T(lang)
		v := reflect.ValueOf(s)
		tp := v.Type()
		for i := 0; i < v.NumField(); i++ {
			f := v.Field(i)
			switch f.Kind() {
			case reflect.String:
				checkValue(lang, tp.Field(i).Name, f.String())
			case reflect.Array:
				for j := 0; j < f.Len(); j++ {
					checkValue(lang, tp.Field(i).Name, f.Index(j).String())
				}
			}
		}
		if s.BtnGrantPerm != s.WizardStep1Grant {
			t.Fatalf("%s permission verb mismatch: BtnGrantPerm=%q WizardStep1Grant=%q", lang, s.BtnGrantPerm, s.WizardStep1Grant)
		}
	}

	if T(LangZH).BadgeGuardPriority != "自动守护中-首选" {
		t.Fatalf("unexpected BadgeGuardPriority: %q", T(LangZH).BadgeGuardPriority)
	}
	if T(LangZH).BackupSlotLabel != "备用" {
		t.Fatalf("unexpected BackupSlotLabel: %q", T(LangZH).BackupSlotLabel)
	}
}

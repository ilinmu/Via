package i18n

import (
	"reflect"
	"testing"
)

func TestCatalogCompleteness(t *testing.T) {
	for _, lang := range []Lang{LangZH, LangEN} {
		s := T(lang)
		v := reflect.ValueOf(s)
		tp := v.Type()
		for i := 0; i < v.NumField(); i++ {
			f := v.Field(i)
			switch f.Kind() {
			case reflect.String:
				if f.String() == "" {
					t.Fatalf("%s field %s is empty", lang, tp.Field(i).Name)
				}
			case reflect.Array:
				for j := 0; j < f.Len(); j++ {
					if f.Index(j).String() == "" {
						t.Fatalf("%s field %s[%d] is empty", lang, tp.Field(i).Name, j)
					}
				}
			}
		}
	}
	if T(LangZH).BadgeGuardPriority != "自动守护中-首选" {
		t.Fatalf("unexpected BadgeGuardPriority: %q", T(LangZH).BadgeGuardPriority)
	}
	if T(LangZH).BackupSlotLabel != "备路径 · 备用" {
		t.Fatalf("unexpected BackupSlotLabel: %q", T(LangZH).BackupSlotLabel)
	}
}

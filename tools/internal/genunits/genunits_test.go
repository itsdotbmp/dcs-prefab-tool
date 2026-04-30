package genunits

import "testing"

func TestEntryZeroValue(t *testing.T) {
	var e Entry
	if e.Type != "" || e.Category != "" || len(e.Attributes) != 0 || e.Origin != "" || e.Folder != "" {
		t.Errorf("expected zero Entry to have empty fields, got %+v", e)
	}
}

func TestRunStubReturnsNoError(t *testing.T) {
	_, _, err := Run(Options{})
	if err != nil {
		t.Errorf("stub Run should not error, got %v", err)
	}
}

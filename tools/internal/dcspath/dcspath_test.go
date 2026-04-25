package dcspath

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverFromConfig(t *testing.T) {
	configDir := t.TempDir()
	savedGames := t.TempDir()
	configPath := filepath.Join(configDir, "config.toml")

	content := `saved_games = ` + tomlString(savedGames) + "\n"
	if err := os.WriteFile(configPath, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := DiscoverFromConfig(configPath)
	if err != nil {
		t.Fatalf("DiscoverFromConfig: %v", err)
	}
	if got != savedGames {
		t.Errorf("got %q want %q", got, savedGames)
	}
}

func TestDiscoverFromEnv(t *testing.T) {
	want := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", want)
	got, ok := DiscoverFromEnv()
	if !ok {
		t.Fatal("expected ok=true with env var set")
	}
	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}

func TestSaveConfig(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "subdir", "config.toml")
	if err := SaveConfig(configPath, "C:\\Users\\X\\Saved Games\\DCS"); err != nil {
		t.Fatalf("SaveConfig: %v", err)
	}
	got, err := DiscoverFromConfig(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if got != "C:\\Users\\X\\Saved Games\\DCS" {
		t.Errorf("round-trip failed: got %q", got)
	}
}

// tomlString quotes a string for TOML, escaping backslashes and quotes.
func tomlString(s string) string {
	out := "\""
	for _, r := range s {
		switch r {
		case '\\':
			out += "\\\\"
		case '"':
			out += "\\\""
		default:
			out += string(r)
		}
	}
	return out + "\""
}

func TestParseTomlString(t *testing.T) {
	cases := []struct {
		name    string
		raw     string
		want    string
		wantErr bool
	}{
		{"plain", `"hello"`, "hello", false},
		{"backslash escape", `"a\\b"`, `a\b`, false},
		{"quote escape", `"he said \"hi\""`, `he said "hi"`, false},
		{"newline escape", `"line1\nline2"`, "line1\nline2", false},
		{"tab escape", `"a\tb"`, "a\tb", false},
		{"unquoted error", `hello`, "", true},
		{"trailing backslash error", `"foo\`, "", true},
		{"unknown escape error", `"\z"`, "", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseTomlString(tc.raw)
			if tc.wantErr {
				if err == nil {
					t.Errorf("expected error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q want %q", got, tc.want)
			}
		})
	}
}

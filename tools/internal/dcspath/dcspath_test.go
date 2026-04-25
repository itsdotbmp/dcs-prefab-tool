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

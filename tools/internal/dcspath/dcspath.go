// Package dcspath discovers the user's DCS Saved Games folder. The Saved
// Games path is needed by every CLI subcommand to locate the dcs-sms
// mailbox.
//
// Discovery order:
//
//  1. --saved-games flag (handled by callers, passed in directly)
//  2. DCS_SMS_SAVED_GAMES environment variable
//  3. config file at the user's config dir (~/.config/dcs-sms/config.toml or
//     %AppData%\dcs-sms\config.toml)
//  4. Default: %USERPROFILE%\Saved Games\DCS or DCS.openbeta (whichever exists)
package dcspath

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// DefaultConfigPath returns the config file path for the current user.
func DefaultConfigPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "dcs-sms", "config.toml"), nil
}

// DiscoverFromEnv returns the path from the DCS_SMS_SAVED_GAMES env var.
func DiscoverFromEnv() (string, bool) {
	v := os.Getenv("DCS_SMS_SAVED_GAMES")
	if v == "" {
		return "", false
	}
	return v, true
}

// DiscoverFromConfig parses the config file and returns the saved_games
// value. Returns an error if the file is missing or the key isn't set.
func DiscoverFromConfig(configPath string) (string, error) {
	f, err := os.Open(configPath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		if strings.TrimSpace(k) != "saved_games" {
			continue
		}
		return parseTomlString(strings.TrimSpace(v))
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", errors.New("saved_games key not found in config")
}

// SaveConfig writes saved_games = "<path>" to configPath, creating parent
// directories as needed.
func SaveConfig(configPath, savedGamesPath string) error {
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		return err
	}
	content := fmt.Sprintf("saved_games = %s\n", encodeTomlString(savedGamesPath))
	return os.WriteFile(configPath, []byte(content), 0o644)
}

// DiscoverDefault returns the conventional Windows path:
//   %USERPROFILE%\Saved Games\DCS  (or DCS.openbeta)
// whichever exists. Returns ("", false) if neither exists or we're not on
// Windows.
func DiscoverDefault() (string, bool) {
	if runtime.GOOS != "windows" {
		return "", false
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", false
	}
	for _, sub := range []string{"DCS", "DCS.openbeta", "DCS.server"} {
		p := filepath.Join(home, "Saved Games", sub)
		if info, err := os.Stat(p); err == nil && info.IsDir() {
			return p, true
		}
	}
	return "", false
}

// Discover applies the full priority order. The override argument lets a
// CLI flag take precedence over everything else.
func Discover(override, configPath string) (string, error) {
	if override != "" {
		return override, nil
	}
	if v, ok := DiscoverFromEnv(); ok {
		return v, nil
	}
	if configPath != "" {
		if v, err := DiscoverFromConfig(configPath); err == nil {
			return v, nil
		}
	}
	if v, ok := DiscoverDefault(); ok {
		return v, nil
	}
	return "", errors.New("could not discover DCS Saved Games path; pass --saved-games or set DCS_SMS_SAVED_GAMES")
}

// parseTomlString parses a basic-string TOML literal: "..." with \" and \\
// escapes. Only the subset we actually emit.
func parseTomlString(raw string) (string, error) {
	if len(raw) < 2 || raw[0] != '"' || raw[len(raw)-1] != '"' {
		return "", fmt.Errorf("expected quoted string, got %q", raw)
	}
	body := raw[1 : len(raw)-1]
	var out strings.Builder
	for i := 0; i < len(body); i++ {
		c := body[i]
		if c != '\\' {
			out.WriteByte(c)
			continue
		}
		if i+1 >= len(body) {
			return "", errors.New("trailing backslash in string")
		}
		switch body[i+1] {
		case '\\':
			out.WriteByte('\\')
		case '"':
			out.WriteByte('"')
		case 'n':
			out.WriteByte('\n')
		case 't':
			out.WriteByte('\t')
		default:
			return "", fmt.Errorf("unknown escape \\%c", body[i+1])
		}
		i++
	}
	return out.String(), nil
}

// encodeTomlString returns a TOML basic string for s, escaping \ and ".
func encodeTomlString(s string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, r := range s {
		switch r {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		default:
			out.WriteRune(r)
		}
	}
	out.WriteByte('"')
	return out.String()
}

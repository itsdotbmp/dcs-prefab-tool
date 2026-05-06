package main

import "testing"

func TestTagToVersion(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"me-mod-v0.2.0", "0.2.0"},
		{"framework-v0.10.0", "0.10.0"},
		{"v0.1.0", "0.1.0"},
		{"0.1.0", "0.1.0"},
		{"unknown-track-v1.2.3", "1.2.3"},
		{"", ""},
	}

	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			got := tagToVersion(tc.in)
			if got != tc.want {
				t.Errorf("tagToVersion(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

package main

import "testing"

func TestCompareVersion(t *testing.T) {
	cases := []struct {
		name string
		a, b string
		want int
	}{
		{"a less than b — minor bump", "0.1.0", "0.2.0", -1},
		{"a greater than b — minor bump", "0.2.0", "0.1.0", +1},
		{"equal", "0.1.0", "0.1.0", 0},
		{"prerelease is older than release", "0.1.0-dev", "0.1.0", -1},
		{"release is newer than prerelease", "0.1.0", "0.1.0-dev", +1},
		{"prereleases equal", "0.1.0-dev", "0.1.0-dev", 0},
		{"v prefix is stripped (a)", "v0.1.0", "0.1.0", 0},
		{"v prefix is stripped (b)", "0.1.0", "v0.1.0", 0},
		{"v prefix on both", "v1.2.3", "v1.2.4", -1},
		{"numeric not lexical compare", "0.10.0", "0.9.0", +1},
		{"unparseable a returns 0", "garbage", "0.1.0", 0},
		{"unparseable b returns 0", "0.1.0", "garbage", 0},
		{"both empty", "", "", 0},
		{"prerelease lexical compare", "0.1.0-alpha", "0.1.0-beta", -1},
		{"major bump dominates", "1.0.0", "0.99.99", +1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := compareVersion(tc.a, tc.b)
			if got != tc.want {
				t.Errorf("compareVersion(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
			}
		})
	}
}

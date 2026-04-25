// Package mailbox handles the on-disk mailbox under
// Saved Games/DCS*/dcs-sms/. It exposes atomic write primitives plus
// higher-level helpers for writing requests and reading responses.
package mailbox

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
)

// WriteAtomic writes data to dst by writing to a sibling temp file and
// renaming. On Windows NTFS, in-folder rename is atomic enough that a
// concurrent reader never sees a partial file.
//
// The parent directory of dst must already exist; WriteAtomic does not
// create directories.
func WriteAtomic(dst string, data []byte) error {
	tmp, err := tempSibling(dst)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, dst); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// tempSibling returns a unique sibling path for dst with a .tmp suffix.
// We need uniqueness because two writers could race on the same dst.
func tempSibling(dst string) (string, error) {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("rand: %w", err)
	}
	return dst + "." + hex.EncodeToString(b[:]) + ".tmp", nil
}

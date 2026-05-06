package main

import (
	"fmt"
	"io"
	"os"
)

const oldSuffix = ".old"

// swapBinary replaces targetPath with the contents read from newBytes.
//
// Strategy:
//  1. Remove any stale targetPath+".old" (Windows refuses rename if it
//     exists).
//  2. Rename targetPath -> targetPath+".old".
//  3. Create targetPath, copy newBytes into it, fsync, close.
//  4. On any failure after step 2, attempt to roll back by removing the
//     partial new file and renaming .old back to targetPath.
//
// On Windows, os.Rename works on a running .exe (the OS allows renaming
// a file even when its handle is locked, though it cannot be unlinked).
// On Unix the same call works because file handles reference inodes
// directly, not paths.
//
// A leftover targetPath+".old" file after a successful swap is harmless
// and is not cleaned up here; the caller decides whether to advertise
// it for manual deletion.
func swapBinary(targetPath string, newBytes io.Reader) error {
	oldPath := targetPath + oldSuffix

	// Step 1: clear any stale .old.
	if _, err := os.Stat(oldPath); err == nil {
		if err := os.Remove(oldPath); err != nil {
			return fmt.Errorf("remove stale %s: %w", oldPath, err)
		}
	}

	// Step 2: rename current -> .old.
	if err := os.Rename(targetPath, oldPath); err != nil {
		return fmt.Errorf("rename %s -> %s: %w", targetPath, oldPath, err)
	}

	rollback := func() {
		_ = os.Remove(targetPath)          // remove partial new file if it exists
		_ = os.Rename(oldPath, targetPath) // restore the original
	}

	// Step 3: write new bytes to targetPath.
	dst, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		rollback()
		return fmt.Errorf("create %s: %w", targetPath, err)
	}

	if _, err := io.Copy(dst, newBytes); err != nil {
		_ = dst.Close()
		rollback()
		return fmt.Errorf("write %s: %w", targetPath, err)
	}

	if err := dst.Sync(); err != nil {
		_ = dst.Close()
		rollback()
		return fmt.Errorf("sync %s: %w", targetPath, err)
	}

	if err := dst.Close(); err != nil {
		rollback()
		return fmt.Errorf("close %s: %w", targetPath, err)
	}

	return nil
}

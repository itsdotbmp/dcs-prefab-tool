//go:build windows

package main

import (
	"errors"
	"flag"
	"fmt"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

func init() {
	register("screenshot", screenshotCmd)
}

func screenshotCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("screenshot", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagOut := fs.String("out", "", "output PNG path (default: %TEMP%/dcs-sms-screenshot.png)")
	flagTitle := fs.String("title", "Digital Combat Simulator", "window title substring (case-insensitive)")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	out := *flagOut
	if out == "" {
		out = filepath.Join(os.TempDir(), "dcs-sms-screenshot.png")
	}

	hwnd, foundTitle, err := findWindowByTitle(*flagTitle)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms screenshot:", err)
		return 3
	}

	img, err := captureWindow(hwnd)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms screenshot: capture:", err)
		return 3
	}

	f, err := os.Create(out)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms screenshot: create:", err)
		return 3
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		fmt.Fprintln(stderr, "dcs-sms screenshot: encode:", err)
		return 3
	}
	fmt.Fprintf(stdout, "captured %dx%d from %q to %s\n",
		img.Bounds().Dx(), img.Bounds().Dy(), foundTitle, out)
	return 0
}

var (
	user32                     = syscall.NewLazyDLL("user32.dll")
	gdi32                      = syscall.NewLazyDLL("gdi32.dll")
	procEnumWindows            = user32.NewProc("EnumWindows")
	procGetWindowTextW         = user32.NewProc("GetWindowTextW")
	procIsWindowVisible        = user32.NewProc("IsWindowVisible")
	procGetWindowRect          = user32.NewProc("GetWindowRect")
	procGetWindowDC            = user32.NewProc("GetWindowDC")
	procReleaseDC              = user32.NewProc("ReleaseDC")
	procPrintWindow            = user32.NewProc("PrintWindow")
	procCreateCompatibleDC     = gdi32.NewProc("CreateCompatibleDC")
	procCreateDIBSection       = gdi32.NewProc("CreateDIBSection")
	procSelectObject           = gdi32.NewProc("SelectObject")
	procDeleteObject           = gdi32.NewProc("DeleteObject")
	procDeleteDC               = gdi32.NewProc("DeleteDC")
)

const (
	pwRenderFullContent = 0x00000002
	biRGB               = 0
	dibRGBColors        = 0
)

type rect struct {
	Left, Top, Right, Bottom int32
}

type bitmapInfoHeader struct {
	BiSize          uint32
	BiWidth         int32
	BiHeight        int32
	BiPlanes        uint16
	BiBitCount      uint16
	BiCompression   uint32
	BiSizeImage     uint32
	BiXPelsPerMeter int32
	BiYPelsPerMeter int32
	BiClrUsed       uint32
	BiClrImportant  uint32
}

type bitmapInfo struct {
	BmiHeader bitmapInfoHeader
	BmiColors [1]uint32
}

func findWindowByTitle(needle string) (syscall.Handle, string, error) {
	needle = strings.ToLower(needle)
	var found syscall.Handle
	var foundTitle string
	cb := syscall.NewCallback(func(hwnd syscall.Handle, _ uintptr) uintptr {
		visible, _, _ := procIsWindowVisible.Call(uintptr(hwnd))
		if visible == 0 {
			return 1
		}
		var buf [512]uint16
		n, _, _ := procGetWindowTextW.Call(
			uintptr(hwnd),
			uintptr(unsafe.Pointer(&buf[0])),
			uintptr(len(buf)),
		)
		if n == 0 {
			return 1
		}
		title := syscall.UTF16ToString(buf[:n])
		if strings.Contains(strings.ToLower(title), needle) {
			found = hwnd
			foundTitle = title
			return 0
		}
		return 1
	})
	procEnumWindows.Call(cb, 0)
	if found == 0 {
		return 0, "", fmt.Errorf("no visible window matched %q", needle)
	}
	return found, foundTitle, nil
}

func captureWindow(hwnd syscall.Handle) (*image.RGBA, error) {
	var r rect
	ok, _, _ := procGetWindowRect.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&r)))
	if ok == 0 {
		return nil, errors.New("GetWindowRect failed")
	}
	width := int(r.Right - r.Left)
	height := int(r.Bottom - r.Top)
	if width <= 0 || height <= 0 {
		return nil, errors.New("window rect is empty")
	}

	hdcWindow, _, _ := procGetWindowDC.Call(uintptr(hwnd))
	if hdcWindow == 0 {
		return nil, errors.New("GetWindowDC failed")
	}
	defer procReleaseDC.Call(uintptr(hwnd), hdcWindow)

	hdcMem, _, _ := procCreateCompatibleDC.Call(hdcWindow)
	if hdcMem == 0 {
		return nil, errors.New("CreateCompatibleDC failed")
	}
	defer procDeleteDC.Call(hdcMem)

	bi := bitmapInfo{
		BmiHeader: bitmapInfoHeader{
			BiSize:        uint32(unsafe.Sizeof(bitmapInfoHeader{})),
			BiWidth:       int32(width),
			BiHeight:      -int32(height), // top-down DIB
			BiPlanes:      1,
			BiBitCount:    32,
			BiCompression: biRGB,
		},
	}
	var bits unsafe.Pointer
	hbm, _, _ := procCreateDIBSection.Call(
		hdcMem,
		uintptr(unsafe.Pointer(&bi)),
		dibRGBColors,
		uintptr(unsafe.Pointer(&bits)),
		0, 0,
	)
	if hbm == 0 || bits == nil {
		return nil, errors.New("CreateDIBSection failed")
	}
	defer procDeleteObject.Call(hbm)

	oldObj, _, _ := procSelectObject.Call(hdcMem, hbm)
	defer procSelectObject.Call(hdcMem, oldObj)

	pwOK, _, _ := procPrintWindow.Call(uintptr(hwnd), hdcMem, pwRenderFullContent)
	if pwOK == 0 {
		return nil, errors.New("PrintWindow failed (try windowed/borderless mode)")
	}

	n := width * height * 4
	src := unsafe.Slice((*byte)(bits), n)

	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for i := 0; i < n; i += 4 {
		img.Pix[i+0] = src[i+2] // BGRA -> RGBA
		img.Pix[i+1] = src[i+1]
		img.Pix[i+2] = src[i+0]
		img.Pix[i+3] = 0xFF
	}
	return img, nil
}

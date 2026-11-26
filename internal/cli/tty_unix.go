//go:build darwin || linux || freebsd || openbsd || netbsd

package cli

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

func readPasswordPrompt(r io.Reader, w io.Writer, prompt string) (string, error) {
	fmt.Fprint(w, prompt)
	if f, ok := r.(*os.File); ok {
		if info, err := f.Stat(); err == nil && (info.Mode()&os.ModeCharDevice) != 0 {
			cmdOff := exec.Command("stty", "-echo")
			cmdOff.Stdin = f
			if err := cmdOff.Run(); err == nil {
				defer func() {
					cmdOn := exec.Command("stty", "echo")
					cmdOn.Stdin = f
					_ = cmdOn.Run()
					fmt.Fprintln(w)
				}()
			}
		}
	}
	br := bufio.NewReader(r)
	line, err := br.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

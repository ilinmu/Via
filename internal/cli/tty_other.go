//go:build !darwin && !linux && !freebsd && !openbsd && !netbsd

package cli

import (
	"bufio"
	"fmt"
	"io"
	"strings"
)

func readPasswordPrompt(r io.Reader, w io.Writer, prompt string) (string, error) {
	fmt.Fprint(w, prompt)
	br := bufio.NewReader(r)
	line, err := br.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

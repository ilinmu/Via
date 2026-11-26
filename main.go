package main

import (
	"os"

	"via/internal/cli"
	"via/internal/uiapp"
)

func main() {
	if len(os.Args) > 1 && cli.IsSubcommand(os.Args[1]) {
		os.Exit(cli.Run(os.Args[1:]))
	}
	uiapp.Run()
}

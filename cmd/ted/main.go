package main

import (
	"log"
	"os"
	"strconv"

	arg "github.com/alexflint/go-arg"
	toml "github.com/pelletier/go-toml"
)

func main() {
	var args struct {
		Path  string `arg:"-p" help:".-separated path for the value to change"`
		Value string `arg:"-v" help:"value in file to set"`
		File  string `arg:"-f" help:"TOML file to modify; otherwise reads from stdin and writes to stdout"`
		Type  string `arg:"-t" help:"type of value (int,string) (default string)"`
	}
	args.Type = "s"
	arg.MustParse(&args)

	in := os.Stdin
	if args.File != "" {
		f, err := os.Open(args.File)
		if err != nil {
			log.Fatal(err)
		}
		in = f
	}

	tree, err := toml.LoadReader(in)
	in.Close()
	if err != nil {
		log.Fatal(err)
	}

	if args.Path != "" {
		var value interface{}
		switch args.Type {
		case "s", "string":
			value = args.Value
		case "i", "int":
			v, err := strconv.Atoi(args.Value)
			if err != nil {
				log.Fatal(err)
			}
			value = int64(v)
		}
		tree.Set(args.Path, value)
	}

	out := os.Stdout
	if args.File != "" {
		f, err := os.Create(args.File)
		if err != nil {
			log.Fatal(err)
		}
		defer f.Close()
		out = f
	}
	_, err = tree.WriteTo(out)
	if err != nil {
		log.Fatal(err)
	}
}

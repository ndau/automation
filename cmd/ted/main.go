package main

import (
	"log"
	"os"
	"strconv"
	"strings"
	"time"

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
		case "b", "bool":
			switch strings.ToLower(args.Value) {
			case "t", "true", "yes", "y":
				value = true
			case "f", "false", "no", "n":
				value = false
			default:
				log.Fatal(args.Value + " could not be interpreted as boolean")
			}
		case "i", "int":
			v, err := strconv.ParseInt(args.Value, 10, 64)
			if err != nil {
				log.Fatal(err)
			}
			value = v
		case "u", "uint":
			v, err := strconv.ParseUint(args.Value, 10, 64)
			if err != nil {
				log.Fatal(err)
			}
			value = v
		case "f", "float":
			v, err := strconv.ParseFloat(args.Value, 64)
			if err != nil {
				log.Fatal(err)
			}
			value = v
		case "t", "time", "timestamp":
			v, err := time.Parse(time.RFC3339, args.Value)
			if err != nil {
				log.Fatal(err)
			}
			value = v
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

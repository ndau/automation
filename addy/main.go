package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"os"

	"github.com/tendermint/ed25519"
)

func main() {

	// Read from stdin
	stat, err := os.Stdin.Stat()
	if err != nil {
		panic(err)
	}

	// is not piped
	if stat.Mode()&os.ModeCharDevice != 0 {
		fmt.Fprintln(os.Stderr, "Usage: echo \"base64-Ed25519-priv-key\" | ./address")
		os.Exit(1)
	}

	// no input
	if stat.Size() <= 0 {
		fmt.Fprintln(os.Stderr, "Warning, no input")
		os.Exit(0)
	}

	jsonB64, err := ioutil.ReadAll(os.Stdin) // not expecting big inputs
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading from stdin: %v", err)
		os.Exit(1)
	}

	// decode b64 to regular bytes
	jsonB := make([]byte, base64.StdEncoding.DecodedLen(len(jsonB64)))
	n, err := base64.StdEncoding.Decode(jsonB, jsonB64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error decoding base64: %v.", err)
		os.Exit(1)
	}
	if n != 64 {
		fmt.Fprintf(os.Stderr, "Expecting 64 bytes. Got %v.", n)
		os.Exit(1)
	}

	// actually make the id
	var privKeyBytes [64]byte
	copy(privKeyBytes[:], jsonB)
	pubBytes := *ed25519.MakePublicKey(&privKeyBytes)
	pubHash := sha256.Sum256(pubBytes[:])

	// output the hexbytes to stdout
	fmt.Printf(hex.EncodeToString(pubHash[:20]))

}

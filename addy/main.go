package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io/ioutil"
	"os"

	"github.com/tendermint/ed25519"
)

func readStdin() ([]byte, error) {
	// Read from stdin
	stat, err := os.Stdin.Stat()
	if err != nil {
		panic(err)
	}

	// is not piped
	if stat.Mode()&os.ModeCharDevice != 0 {
		return nil, errors.New("Usage: echo \"base64-Ed25519-priv-key\" | ./address")
	}

	jsonB64, err := ioutil.ReadAll(os.Stdin) // not expecting big inputs
	if err != nil {
		return nil, fmt.Errorf("Error reading from stdin: %v", err)
	}

	return jsonB64, nil
}

func makeAddressHash(jsonB64 []byte) (string, error) {

	// decode b64 to regular bytes
	jsonB := make([]byte, base64.StdEncoding.DecodedLen(len(jsonB64)))
	n, err := base64.StdEncoding.Decode(jsonB, jsonB64)
	if err != nil {
		return "", fmt.Errorf("error decoding base64: %v", err)
	}
	if n != 64 {
		return "", fmt.Errorf("expecting 64 bytes. Got %v", n)
	}

	// actually make the id
	var privKeyBytes [64]byte
	copy(privKeyBytes[:], jsonB)
	pubBytes := *ed25519.MakePublicKey(&privKeyBytes)
	pubHash := sha256.Sum256(pubBytes[:])
	trunc := pubHash[:20]
	hex := hex.EncodeToString(trunc)

	return hex, nil
}

func main() {

	// Read from stdin
	jsonB64, err := readStdin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Could not read from stdin: %v\n", err)
		os.Exit(1)
	}

	// decode b64 to regular bytes. actually make the id
	hex, err := makeAddressHash(jsonB64)

	// output the hexbytes to stdout
	fmt.Printf(hex)

}

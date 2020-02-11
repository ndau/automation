package main

// ----- ---- --- -- -
// Copyright 2020 The Axiom Foundation. All Rights Reserved.
//
// Licensed under the Apache License 2.0 (the "License").  You may not use
// this file except in compliance with the License.  You can obtain a copy
// in the file LICENSE in the source distribution or at
// https://www.apache.org/licenses/LICENSE-2.0.txt
// - -- --- ---- -----

import (
	"bytes"
	"io/ioutil"
	"log"
	"os"
	"testing"
)

// TODO For the moment these tests only test for correct output.
// They don't trigger all the errors.

func TestReadStdin(t *testing.T) {

	testBytes := []byte("YWxsIHlvdXIgYmFzZTY0IGFyZSBiZWxvbmcgdG8gdXM=")

	tmpfile, err := ioutil.TempFile("", "tmp")
	if err != nil {
		log.Fatal(err)
	}

	defer os.Remove(tmpfile.Name()) // clean up

	if _, err := tmpfile.Write(testBytes); err != nil {
		log.Fatal(err)
	}

	if _, err := tmpfile.Seek(0, 0); err != nil {
		log.Fatal(err)
	}

	oldStdin := os.Stdin
	defer func() { os.Stdin = oldStdin }() // Restore original Stdin

	os.Stdin = tmpfile
	b64, err := readStdin()
	if err != nil {
		t.Errorf("readStdin failed: %v", err)
	}

	if !bytes.Equal(b64, testBytes) {
		t.Errorf("readStdin failed. Expected: \n%v, \ngot: \n%v", testBytes, b64)
	}

	if err := tmpfile.Close(); err != nil {
		log.Fatal(err)
	}
}

func TestAddressHash(t *testing.T) {

	input := []byte("V2Ugc2V0IHlvdSB1cCB0aGUgYm9tYi4gOmdhc3A6IEFsbCB5b3VyIGJhc2U2NCBhcmUgYmVsb25nIHRvIHVzLg==")
	const expected = "47b1c8dbdded736f5c9174965794137ed580c935"

	got, err := makeAddressHash(input)
	if err != nil {
		t.Errorf("makeAddressHash failed: %v", err)
	}

	if got != expected {
		t.Errorf("makeAddressHash failed: got %v, expected %v", got, expected)
	}
}

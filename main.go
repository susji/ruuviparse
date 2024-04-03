package main

import (
	"bufio"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/susji/ruuvi/data/rawv2"
)

func main() {
	var mode string
	flag.StringVar(&mode, "mode", "hex", "Input mode: raw, hex, or base64")
	flag.Parse()

	var dec func([]byte) ([]byte, error)
	switch mode {
	case "raw":
		dec = func(b []byte) ([]byte, error) {
			return b, nil
		}
	case "hex":
		dec = func(b []byte) ([]byte, error) {
			return hex.AppendDecode([]byte{}, b)
		}
	case "base64":
		dec = func(b []byte) ([]byte, error) {
			return base64.StdEncoding.AppendDecode([]byte{}, b)
		}
	default:
		fmt.Fprintln(os.Stderr, "unknown mode:, mode")
		os.Exit(1)
	}

	s := bufio.NewScanner(os.Stdin)
	fmt.Fprintln(os.Stderr, "reading standard input as", mode)
	for s.Scan() {
		if err := s.Err(); err != nil {
			fmt.Fprintln(os.Stderr, "reading input failed:", err)
			continue // Maybe depart?
		}
		d, err := dec(s.Bytes())
		if err != nil {
			fmt.Fprintln(os.Stderr, "decoding input failed:", err)
			continue
		}
		p, err := rawv2.Parse(d)
		if err != nil {
			fmt.Fprintln(os.Stderr, "parsing input failed:", err)
			continue
		}
		out, err := json.Marshal(&p)
		if err != nil {
			fmt.Fprintln(os.Stderr, "packet json marshal failed:", err)
			continue
		}
		fmt.Println(string(out))
	}
}

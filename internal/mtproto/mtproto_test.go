package mtproto

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"testing"
)

func TestDCFromInit(t *testing.T) {
	init := makeInitPacket(t, ProtoIntermediate, -4)

	dc, isMedia, proto, err := DCFromInit(init)
	if err != nil {
		t.Fatalf("DCFromInit returned error: %v", err)
	}
	if dc != 4 {
		t.Fatalf("unexpected dc: %d", dc)
	}
	if !isMedia {
		t.Fatal("expected media flag")
	}
	if proto != ProtoIntermediate {
		t.Fatalf("unexpected proto: 0x%08x", proto)
	}
}

func TestPatchInitDC(t *testing.T) {
	init := makeInitPacket(t, ProtoAbridged, 2)

	patched, err := PatchInitDC(init, -5)
	if err != nil {
		t.Fatalf("PatchInitDC returned error: %v", err)
	}

	dc, isMedia, proto, err := DCFromInit(patched)
	if err != nil {
		t.Fatalf("DCFromInit returned error after patch: %v", err)
	}
	if dc != 5 || !isMedia || proto != ProtoAbridged {
		t.Fatalf("unexpected parsed values after patch: dc=%d media=%v proto=0x%08x", dc, isMedia, proto)
	}
}

func TestParseInitUnknownDCStillReturnsProto(t *testing.T) {
	init := makeInitPacket(t, ProtoPaddedIntermediate, 100)

	info, err := ParseInit(init)
	if err != nil {
		t.Fatalf("ParseInit returned error: %v", err)
	}
	if info.DC != 0 {
		t.Fatalf("expected unknown dc to map to 0, got %d", info.DC)
	}
	if info.Proto != ProtoPaddedIntermediate {
		t.Fatalf("unexpected proto: 0x%08x", info.Proto)
	}
}

func TestIsHTTPTransport(t *testing.T) {
	if !IsHTTPTransport([]byte("POST / HTTP/1.1")) {
		t.Fatal("expected POST transport to be detected")
	}
	if IsHTTPTransport([]byte{0xef, 0xef, 0xef, 0xef}) {
		t.Fatal("did not expect mtproto bytes to look like http")
	}
}

func TestSplitterIntermediate(t *testing.T) {
	init := makeInitPacket(t, ProtoIntermediate, 2)
	splitter, err := NewSplitter(init, ProtoIntermediate)
	if err != nil {
		t.Fatalf("NewSplitter returned error: %v", err)
	}

	plain1 := makeIntermediatePacket([]byte("hello"))
	plain2 := makeIntermediatePacket([]byte("world!"))
	cipherText := encryptAfterInit(t, init, append(plain1, plain2...))

	parts := splitter.Split(cipherText[:7])
	if len(parts) != 0 {
		t.Fatalf("expected no packet after partial split, got %d", len(parts))
	}

	parts = splitter.Split(cipherText[7:11])
	if len(parts) != 1 {
		t.Fatalf("expected first packet after completing split, got %d", len(parts))
	}
	if !bytes.Equal(parts[0], cipherText[:len(plain1)]) {
		t.Fatal("first packet ciphertext boundary mismatch")
	}

	parts = splitter.Split(cipherText[11:])
	if len(parts) != 1 {
		t.Fatalf("expected second packet after tail split, got %d", len(parts))
	}
	if !bytes.Equal(parts[0], cipherText[len(plain1):]) {
		t.Fatal("second packet ciphertext boundary mismatch")
	}
}

func makeInitPacket(t *testing.T, proto uint32, dc int16) []byte {
	t.Helper()

	init := make([]byte, 64)
	for i := range init {
		init[i] = byte(i + 1)
	}

	var plain [8]byte
	binary.LittleEndian.PutUint32(plain[:4], proto)
	binary.LittleEndian.PutUint16(plain[4:6], uint16(dc))

	keystream := initKeystreamForTest(t, init)
	for i := 0; i < len(plain); i++ {
		init[56+i] = plain[i] ^ keystream[56+i]
	}
	return init
}

func makeIntermediatePacket(payload []byte) []byte {
	out := make([]byte, 4+len(payload))
	binary.LittleEndian.PutUint32(out[:4], uint32(len(payload)))
	copy(out[4:], payload)
	return out
}

func encryptAfterInit(t *testing.T, init []byte, plain []byte) []byte {
	t.Helper()

	block, err := aes.NewCipher(init[8:40])
	if err != nil {
		t.Fatalf("aes.NewCipher failed: %v", err)
	}
	stream := cipher.NewCTR(block, init[40:56])
	zero := make([]byte, 64)
	stream.XORKeyStream(zero, zero)

	out := append([]byte(nil), plain...)
	stream.XORKeyStream(out, out)
	return out
}

func decryptAfterInit(t *testing.T, init []byte, cipherText []byte) []byte {
	t.Helper()
	return encryptAfterInit(t, init, cipherText)
}

func initKeystreamForTest(t *testing.T, init []byte) []byte {
	t.Helper()
	ks, err := initKeystream(init)
	if err != nil {
		t.Fatalf("initKeystream failed: %v", err)
	}
	return ks
}

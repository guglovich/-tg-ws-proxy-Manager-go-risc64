package mtproto

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"errors"
)

const (
	ProtoAbridged           uint32 = 0xEFEFEFEF
	ProtoIntermediate       uint32 = 0xEEEEEEEE
	ProtoPaddedIntermediate uint32 = 0xDDDDDDDD
	initPacketSize                 = 64
)

var (
	ErrInitTooShort = errors.New("mtproto init packet is too short")
	ErrInvalidProto = errors.New("invalid mtproto transport protocol")
)

type InitInfo struct {
	DC      int
	IsMedia bool
	Proto   uint32
}

type Splitter struct {
	stream    cipher.Stream
	proto     uint32
	cipherBuf []byte
	plainBuf  []byte
	disabled  bool
}

func IsHTTPTransport(data []byte) bool {
	return len(data) >= 4 && (hasPrefix(data, []byte("POST ")) ||
		hasPrefix(data, []byte("GET ")) ||
		hasPrefix(data, []byte("HEAD ")) ||
		hasPrefix(data, []byte("OPTIONS ")))
}

func ParseInit(data []byte) (InitInfo, error) {
	dc, isMedia, proto, err := DCFromInit(data)
	if err != nil {
		return InitInfo{}, err
	}
	return InitInfo{DC: dc, IsMedia: isMedia, Proto: proto}, nil
}

func DCFromInit(data []byte) (dc int, isMedia bool, proto uint32, err error) {
	if len(data) < initPacketSize {
		return 0, false, 0, ErrInitTooShort
	}

	keystream, err := initKeystream(data)
	if err != nil {
		return 0, false, 0, err
	}

	var plain [8]byte
	for i := 0; i < len(plain); i++ {
		plain[i] = data[56+i] ^ keystream[56+i]
	}

	proto = binary.LittleEndian.Uint32(plain[:4])
	if !validProto(proto) {
		return 0, false, 0, ErrInvalidProto
	}

	dcRaw := int(int16(binary.LittleEndian.Uint16(plain[4:6])))
	dc = abs(dcRaw)
	isMedia = dcRaw < 0

	if dc < 1 || (dc > 5 && dc != 203) {
		return 0, false, proto, nil
	}

	return dc, isMedia, proto, nil
}

func PatchInitDC(data []byte, dc int) ([]byte, error) {
	if len(data) < initPacketSize {
		return nil, ErrInitTooShort
	}

	keystream, err := initKeystream(data)
	if err != nil {
		return nil, err
	}

	out := append([]byte(nil), data...)
	dcBytes := make([]byte, 2)
	binary.LittleEndian.PutUint16(dcBytes, uint16(int16(dc)))
	out[60] = keystream[60] ^ dcBytes[0]
	out[61] = keystream[61] ^ dcBytes[1]
	return out, nil
}

func NewSplitter(initData []byte, proto uint32) (*Splitter, error) {
	if len(initData) < initPacketSize {
		return nil, ErrInitTooShort
	}
	if !validProto(proto) {
		return nil, ErrInvalidProto
	}

	block, err := aes.NewCipher(initData[8:40])
	if err != nil {
		return nil, err
	}
	stream := cipher.NewCTR(block, initData[40:56])

	zero := make([]byte, initPacketSize)
	stream.XORKeyStream(zero, zero)

	return &Splitter{
		stream: stream,
		proto:  proto,
	}, nil
}

func (s *Splitter) Split(chunk []byte) [][]byte {
	if len(chunk) == 0 {
		return nil
	}
	if s.disabled {
		return [][]byte{append([]byte(nil), chunk...)}
	}

	s.cipherBuf = append(s.cipherBuf, chunk...)
	plain := append([]byte(nil), chunk...)
	s.stream.XORKeyStream(plain, plain)
	s.plainBuf = append(s.plainBuf, plain...)

	var parts [][]byte
	for len(s.cipherBuf) > 0 {
		packetLen, ok := s.nextPacketLen()
		if !ok {
			break
		}
		if packetLen <= 0 {
			parts = append(parts, append([]byte(nil), s.cipherBuf...))
			s.cipherBuf = s.cipherBuf[:0]
			s.plainBuf = s.plainBuf[:0]
			s.disabled = true
			break
		}

		parts = append(parts, append([]byte(nil), s.cipherBuf[:packetLen]...))
		s.cipherBuf = append([]byte(nil), s.cipherBuf[packetLen:]...)
		s.plainBuf = append([]byte(nil), s.plainBuf[packetLen:]...)
	}

	return parts
}

func (s *Splitter) Flush() [][]byte {
	if len(s.cipherBuf) == 0 {
		return nil
	}
	tail := append([]byte(nil), s.cipherBuf...)
	s.cipherBuf = s.cipherBuf[:0]
	s.plainBuf = s.plainBuf[:0]
	return [][]byte{tail}
}

func (s *Splitter) nextPacketLen() (int, bool) {
	if len(s.plainBuf) == 0 {
		return 0, false
	}
	switch s.proto {
	case ProtoAbridged:
		return s.nextAbridgedLen()
	case ProtoIntermediate, ProtoPaddedIntermediate:
		return s.nextIntermediateLen()
	default:
		return 0, true
	}
}

func (s *Splitter) nextAbridgedLen() (int, bool) {
	first := s.plainBuf[0]
	var payloadLen int
	headerLen := 1

	if first == 0x7F || first == 0xFF {
		if len(s.plainBuf) < 4 {
			return 0, false
		}
		payloadLen = int(uint32(s.plainBuf[1])|uint32(s.plainBuf[2])<<8|uint32(s.plainBuf[3])<<16) * 4
		headerLen = 4
	} else {
		payloadLen = int(first&0x7F) * 4
	}

	if payloadLen <= 0 {
		return 0, true
	}

	packetLen := headerLen + payloadLen
	if len(s.plainBuf) < packetLen {
		return 0, false
	}
	return packetLen, true
}

func (s *Splitter) nextIntermediateLen() (int, bool) {
	if len(s.plainBuf) < 4 {
		return 0, false
	}
	payloadLen := int(binary.LittleEndian.Uint32(s.plainBuf[:4]) & 0x7FFFFFFF)
	if payloadLen <= 0 {
		return 0, true
	}
	packetLen := 4 + payloadLen
	if len(s.plainBuf) < packetLen {
		return 0, false
	}
	return packetLen, true
}

func initKeystream(data []byte) ([]byte, error) {
	block, err := aes.NewCipher(data[8:40])
	if err != nil {
		return nil, err
	}
	stream := cipher.NewCTR(block, data[40:56])
	zero := make([]byte, initPacketSize)
	keystream := make([]byte, initPacketSize)
	stream.XORKeyStream(keystream, zero)
	return keystream, nil
}

func validProto(proto uint32) bool {
	switch proto {
	case ProtoAbridged, ProtoIntermediate, ProtoPaddedIntermediate:
		return true
	default:
		return false
	}
}

func hasPrefix(data []byte, prefix []byte) bool {
	if len(data) < len(prefix) {
		return false
	}
	for i := range prefix {
		if data[i] != prefix[i] {
			return false
		}
	}
	return true
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

package telegram

import "testing"

func TestIsTelegramIP(t *testing.T) {
	if !IsTelegramIP("149.154.167.220") {
		t.Fatal("expected telegram ip to be recognized")
	}
	if IsTelegramIP("8.8.8.8") {
		t.Fatal("did not expect google dns to be recognized as telegram ip")
	}
}

func TestLookupEndpoint(t *testing.T) {
	ep, ok := LookupEndpoint("149.154.167.220")
	if !ok {
		t.Fatal("expected endpoint lookup to succeed")
	}
	if ep.DC != 2 || ep.IsMedia {
		t.Fatalf("unexpected endpoint: %+v", ep)
	}
}

func TestLookupEndpointIPv6(t *testing.T) {
	ep, ok := LookupEndpoint("2001:67c:4e8:f002::7")
	if !ok {
		t.Fatal("expected ipv6 endpoint lookup to succeed")
	}
	if ep.DC != 2 || ep.IsMedia {
		t.Fatalf("unexpected ipv6 endpoint: %+v", ep)
	}
}

func TestWSDomains(t *testing.T) {
	got := WSDomains(203, false)
	if len(got) != 2 {
		t.Fatalf("unexpected ws domains len: %d", len(got))
	}
	if got[0] != "kws2.web.telegram.org" {
		t.Fatalf("unexpected first ws domain: %q", got[0])
	}
}

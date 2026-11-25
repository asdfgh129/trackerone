package httpapi

import (
	"bytes"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestAdminConsoleServesStaticAssets(t *testing.T) {
	server := newTestServer(t)
	client := server.Client()
	client.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}

	// 无尾斜杠应重定向到 /admin/。
	response, err := client.Get(server.URL + "/admin")
	if err != nil {
		t.Fatalf("admin redirect: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusMovedPermanently {
		t.Fatalf("expected 301, got %d", response.StatusCode)
	}
	if location := response.Header.Get("Location"); location != "/admin/" {
		t.Fatalf("unexpected redirect target: %q", location)
	}

	response, err = client.Get(server.URL + "/admin/")
	if err != nil {
		t.Fatalf("admin index: %v", err)
	}
	body, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("admin index status: %d %s", response.StatusCode, body)
	}
	if !bytes.Contains(body, []byte("运营台")) || !bytes.Contains(body, []byte("/admin/app.js")) {
		t.Fatalf("unexpected admin index: %s", body)
	}
	if csp := response.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") {
		t.Fatalf("missing CSP: %q", csp)
	}
	if csp := response.Header.Get("Content-Security-Policy"); strings.Contains(csp, "unsafe-inline") {
		t.Fatalf("CSP must not allow inline scripts: %q", csp)
	}
	if xfo := response.Header.Get("X-Frame-Options"); xfo != "DENY" {
		t.Fatalf("unexpected X-Frame-Options: %q", xfo)
	}
	if nosniff := response.Header.Get("X-Content-Type-Options"); nosniff != "nosniff" {
		t.Fatalf("unexpected X-Content-Type-Options: %q", nosniff)
	}
	if cache := response.Header.Get("Cache-Control"); cache != "no-store" {
		t.Fatalf("unexpected Cache-Control: %q", cache)
	}

	response, err = client.Get(server.URL + "/admin/app.js")
	if err != nil {
		t.Fatalf("admin js: %v", err)
	}
	script, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("admin js status: %d", response.StatusCode)
	}
	if contentType := response.Header.Get("Content-Type"); !strings.Contains(contentType, "javascript") {
		t.Fatalf("unexpected js content type: %q", contentType)
	}
	if !bytes.Contains(script, []byte("/v1/messages/audit")) {
		t.Fatalf("app.js must call the audit endpoint")
	}
	// 渲染必须使用 textContent，避免把消息正文当 HTML 执行。
	if !bytes.Contains(script, []byte("textContent")) {
		t.Fatalf("app.js must render untrusted content with textContent")
	}

	response, err = client.Get(server.URL + "/admin/app.css")
	if err != nil {
		t.Fatalf("admin css: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("admin css status: %d", response.StatusCode)
	}
	if contentType := response.Header.Get("Content-Type"); !strings.Contains(contentType, "text/css") {
		t.Fatalf("unexpected css content type: %q", contentType)
	}
}

func TestAdminConsoleRejectsWriteMethods(t *testing.T) {
	server := newTestServer(t)
	request, _ := http.NewRequest(http.MethodPost, server.URL+"/admin/", nil)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("admin post: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", response.StatusCode)
	}
	if allow := response.Header.Get("Allow"); !strings.Contains(allow, "GET") {
		t.Fatalf("unexpected Allow header: %q", allow)
	}
}

func TestAdminConsoleDoesNotExposeSources(t *testing.T) {
	server := newTestServer(t)
	for _, path := range []string{
		"/admin/../go.mod",
		"/admin/%2e%2e/go.mod",
		"/admin/index.html.bak",
	} {
		response, err := http.Get(server.URL + path)
		if err != nil {
			t.Fatalf("probe %s: %v", path, err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if response.StatusCode == http.StatusOK && bytes.Contains(body, []byte("module github.com")) {
			t.Fatalf("path traversal leaked go.mod via %s", path)
		}
	}
}

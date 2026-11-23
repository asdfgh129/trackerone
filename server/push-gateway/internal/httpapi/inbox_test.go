package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

func doJSON(t *testing.T, method, url, token string, payload any) (*http.Response, []byte) {
	t.Helper()
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		body = bytes.NewReader(encoded)
	}
	request, err := http.NewRequest(method, url, body)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	raw, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return response, raw
}

func TestInboxSendListAckFlow(t *testing.T) {
	server := newTestServer(t)
	base := server.URL

	// 先注册别名，确保下发时能命中推送。
	response, raw := doJSON(t, http.MethodPost, base+"/v1/aliases", "user-token", map[string]any{
		"alias":    "u42@1",
		"platform": "android",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("register alias: %d %s", response.StatusCode, raw)
	}

	// 管理端下发一条指令消息。
	response, raw = doJSON(t, http.MethodPost, base+"/v1/messages", "admin-token", map[string]any{
		"userId": 42,
		"kind":   "command",
		"title":  "指令：断油",
		"body":   "调度要求断油",
		"data": map[string]any{
			"deviceId": 7,
			"command":  "engineStop",
		},
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("send message: %d %s", response.StatusCode, raw)
	}
	var sent struct {
		Message struct {
			ID        string         `json:"id"`
			Kind      string         `json:"kind"`
			Title     string         `json:"title"`
			Data      map[string]any `json:"data"`
			CreatedAt string         `json:"createdAt"`
			ExpiresAt string         `json:"expiresAt"`
		} `json:"message"`
		Push string `json:"push"`
	}
	if err := json.Unmarshal(raw, &sent); err != nil {
		t.Fatalf("decode send: %v", err)
	}
	if sent.Message.ID == "" || sent.Message.Kind != "command" {
		t.Fatalf("unexpected message: %s", raw)
	}
	if sent.Message.Data["command"] != "engineStop" {
		t.Fatalf("data not preserved: %s", raw)
	}
	if sent.Message.ExpiresAt == "" {
		t.Fatalf("expiresAt missing: %s", raw)
	}
	if sent.Push != "sent" {
		t.Fatalf("expected push sent, got %q", sent.Push)
	}

	// 用户按游标拉取。
	response, raw = doJSON(t, http.MethodGet, base+"/v1/messages?limit=50", "user-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("list: %d %s", response.StatusCode, raw)
	}
	var page struct {
		Messages []struct {
			ID string `json:"id"`
		} `json:"messages"`
		NextCursor string `json:"nextCursor"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(page.Messages) != 1 || page.Messages[0].ID != sent.Message.ID {
		t.Fatalf("unexpected page: %s", raw)
	}
	if page.NextCursor == "" {
		t.Fatalf("nextCursor missing: %s", raw)
	}

	// 用游标再拉一次，不应重复返回。
	response, raw = doJSON(t, http.MethodGet, base+"/v1/messages?since="+page.NextCursor, "user-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("incremental list: %d %s", response.StatusCode, raw)
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatalf("decode incremental: %v", err)
	}
	if len(page.Messages) != 0 {
		t.Fatalf("cursor must advance, got %s", raw)
	}

	// 投递回执幂等。
	for i := 0; i < 2; i++ {
		response, raw = doJSON(t, http.MethodPost, base+"/v1/messages/"+sent.Message.ID+"/ack", "user-token", nil)
		if response.StatusCode != http.StatusNoContent {
			t.Fatalf("ack #%d: %d %s", i, response.StatusCode, raw)
		}
	}
	response, raw = doJSON(t, http.MethodPost, base+"/v1/messages/msg_missing/ack", "user-token", nil)
	if response.StatusCode != http.StatusNotFound {
		t.Fatalf("unknown ack: %d %s", response.StatusCode, raw)
	}

	// 管理端清空后，用户拉不到任何消息。
	response, raw = doJSON(t, http.MethodDelete, base+"/v1/messages?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("delete: %d %s", response.StatusCode, raw)
	}
	_, raw = doJSON(t, http.MethodGet, base+"/v1/messages", "user-token", nil)
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatalf("decode after delete: %v", err)
	}
	if len(page.Messages) != 0 {
		t.Fatalf("inbox not cleared: %s", raw)
	}
}

func TestInboxAuthorization(t *testing.T) {
	server := newTestServer(t)

	response, _ := doJSON(t, http.MethodGet, server.URL+"/v1/messages", "", nil)
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("list without token: %d", response.StatusCode)
	}

	response, _ = doJSON(t, http.MethodPost, server.URL+"/v1/messages", "user-token", map[string]any{
		"userId": 42,
		"kind":   "notice",
		"title":  "unauthorized",
	})
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("send without admin: %d", response.StatusCode)
	}

	response, _ = doJSON(t, http.MethodDelete, server.URL+"/v1/messages?userId=42&serverId=1", "", nil)
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("delete without admin: %d", response.StatusCode)
	}
}

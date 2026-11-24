package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"github.com/trackerone/push-gateway/internal/auth"
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

func TestInboxAuditRevokeAndResend(t *testing.T) {
	server := newTestServer(t)
	base := server.URL

	response, raw := doJSON(t, http.MethodPost, base+"/v1/aliases", "user-token", map[string]any{
		"alias":    "u42@1",
		"platform": "android",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("register alias: %d %s", response.StatusCode, raw)
	}

	response, raw = doJSON(t, http.MethodPost, base+"/v1/messages", "admin-token", map[string]any{
		"userId": 42,
		"kind":   "notice",
		"title":  "审计测试",
		"body":   "hello",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("send: %d %s", response.StatusCode, raw)
	}
	var sent struct {
		Message struct {
			ID string `json:"id"`
		} `json:"message"`
	}
	if err := json.Unmarshal(raw, &sent); err != nil {
		t.Fatalf("decode send: %v", err)
	}
	if sent.Message.ID == "" {
		t.Fatalf("missing id: %s", raw)
	}

	// 审计能看到来源、推送状态与回执时间。
	response, raw = doJSON(t, http.MethodGet, base+"/v1/messages/audit?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("audit: %d %s", response.StatusCode, raw)
	}
	var audit struct {
		Messages []struct {
			ID         string `json:"id"`
			UserID     int64  `json:"userId"`
			ServerID   int64  `json:"serverId"`
			Source     string `json:"source"`
			PushStatus string `json:"pushStatus"`
		} `json:"messages"`
		NextCursor string `json:"nextCursor"`
	}
	if err := json.Unmarshal(raw, &audit); err != nil {
		t.Fatalf("decode audit: %v", err)
	}
	if len(audit.Messages) != 1 {
		t.Fatalf("unexpected audit page: %s", raw)
	}
	entry := audit.Messages[0]
	if entry.ID != sent.Message.ID || entry.UserID != 42 || entry.ServerID != 1 {
		t.Fatalf("unexpected audit entry: %s", raw)
	}
	if entry.Source != "admin" || entry.PushStatus != "sent" {
		t.Fatalf("unexpected audit status: %s", raw)
	}

	// 分页游标。
	response, raw = doJSON(t, http.MethodGet, base+"/v1/messages/audit?userId=42&serverId=1&limit=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("audit page: %d %s", response.StatusCode, raw)
	}
	if err := json.Unmarshal(raw, &audit); err != nil {
		t.Fatalf("decode audit page: %v", err)
	}
	if len(audit.Messages) != 1 || audit.NextCursor == "" {
		t.Fatalf("expected cursor for full page: %s", raw)
	}

	// 重发不新增消息。
	response, raw = doJSON(t, http.MethodPost, base+"/v1/messages/"+sent.Message.ID+"/resend?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("resend: %d %s", response.StatusCode, raw)
	}
	var resent struct {
		Push string `json:"push"`
	}
	if err := json.Unmarshal(raw, &resent); err != nil {
		t.Fatalf("decode resend: %v", err)
	}
	if resent.Push != "sent" {
		t.Fatalf("expected resend push sent, got %s", raw)
	}

	// 撤回后用户拉不到，但审计仍可查。
	response, raw = doJSON(t, http.MethodPost, base+"/v1/messages/"+sent.Message.ID+"/revoke?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("revoke: %d %s", response.StatusCode, raw)
	}
	_, raw = doJSON(t, http.MethodGet, base+"/v1/messages", "user-token", nil)
	var page struct {
		Messages []struct {
			ID string `json:"id"`
		} `json:"messages"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(page.Messages) != 0 {
		t.Fatalf("revoked message must be hidden: %s", raw)
	}

	response, raw = doJSON(t, http.MethodGet, base+"/v1/messages/audit?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("audit after revoke: %d %s", response.StatusCode, raw)
	}
	var revokedAudit struct {
		Messages []struct {
			RevokedAt string `json:"revokedAt"`
		} `json:"messages"`
	}
	if err := json.Unmarshal(raw, &revokedAudit); err != nil {
		t.Fatalf("decode revoked audit: %v", err)
	}
	if len(revokedAudit.Messages) != 1 || revokedAudit.Messages[0].RevokedAt == "" {
		t.Fatalf("revokedAt missing in audit: %s", raw)
	}

	// 撤回后不能重发。
	response, _ = doJSON(t, http.MethodPost, base+"/v1/messages/"+sent.Message.ID+"/resend?userId=42&serverId=1", "admin-token", nil)
	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("resend revoked: %d", response.StatusCode)
	}
}

func TestInboxAdminOrTraccarSignature(t *testing.T) {
	server := newTestServer(t)
	base := server.URL

	if response, _ := doJSON(t, http.MethodPost, base+"/v1/aliases", "user-token", map[string]any{
		"alias":    "u42@1",
		"platform": "android",
	}); response.StatusCode != http.StatusCreated {
		t.Fatalf("register alias: %d", response.StatusCode)
	}

	payload := map[string]any{
		"userId": 42,
		"kind":   "notice",
		"title":  "指令结果",
		"body":   "success",
		"data": map[string]any{
			"eventType": "commandResult",
			"deviceId":  7,
			"result":    "success",
			"success":   true,
		},
	}
	body, _ := json.Marshal(payload)
	request, _ := http.NewRequest(http.MethodPost, base+"/v1/messages", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Traccar-Signature", auth.Sign(secret, body))
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("signed send: %v", err)
	}
	raw, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("signed send: %d %s", response.StatusCode, raw)
	}
	var created struct {
		Message struct {
			Source string `json:"source"`
		} `json:"message"`
	}
	if err := json.Unmarshal(raw, &created); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if created.Message.Source != "traccar" {
		t.Fatalf("expected traccar source, got %s", raw)
	}

	// 伪造签名必须拒绝。
	request, _ = http.NewRequest(http.MethodPost, base+"/v1/messages", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Traccar-Signature", auth.Sign("wrong-secret", body))
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("forged send: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("forged send must be rejected: %d", response.StatusCode)
	}
}

func TestCommandResultEventCreatesInboxMessage(t *testing.T) {
	server := newTestServer(t)
	base := server.URL

	if response, _ := doJSON(t, http.MethodPost, base+"/v1/aliases", "user-token", map[string]any{
		"alias":    "u42@1",
		"platform": "android",
	}); response.StatusCode != http.StatusCreated {
		t.Fatalf("register alias: %d", response.StatusCode)
	}

	payload := map[string]any{
		"version":    1,
		"userId":     42,
		"deviceId":   7,
		"deviceName": "测试车",
		"event": map[string]any{
			"id":       9001,
			"type":     "commandResult",
			"deviceId": 7,
			"attributes": map[string]any{
				"result": "success",
			},
		},
	}
	body, _ := json.Marshal(payload)
	request, _ := http.NewRequest(http.MethodPost, base+"/v1/events", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Traccar-Signature", auth.Sign(secret, body))
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("command result event: %v", err)
	}
	raw, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		t.Fatalf("command result event: %d %s", response.StatusCode, raw)
	}

	_, raw = doJSON(t, http.MethodGet, base+"/v1/messages", "user-token", nil)
	var page struct {
		Messages []struct {
			ID    string         `json:"id"`
			Kind  string         `json:"kind"`
			Data  map[string]any `json:"data"`
			Body  string         `json:"body"`
			Title string         `json:"title"`
		} `json:"messages"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatalf("decode inbox: %v", err)
	}
	if len(page.Messages) != 1 {
		t.Fatalf("expected one command result message: %s", raw)
	}
	message := page.Messages[0]
	if message.Kind != "notice" || message.Body != "success" {
		t.Fatalf("unexpected message: %s", raw)
	}
	if message.Data["eventType"] != "commandResult" || message.Data["deviceId"] != float64(7) {
		t.Fatalf("unexpected data: %s", raw)
	}
	if message.Data["success"] != true {
		t.Fatalf("unexpected success flag: %s", raw)
	}
}

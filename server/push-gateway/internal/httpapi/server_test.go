package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/trackerone/push-gateway/internal/auth"
	"github.com/trackerone/push-gateway/internal/config"
	"github.com/trackerone/push-gateway/internal/gateway"
	"github.com/trackerone/push-gateway/internal/jpush"
	"github.com/trackerone/push-gateway/internal/store"
	"github.com/trackerone/push-gateway/internal/template"
)

const secret = "http-test-secret"

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()

	jpushServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"sendno":"sn","msg_id":1}`))
	}))
	t.Cleanup(jpushServer.Close)

	traccarServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/session":
			_, _ = w.Write([]byte(`{"id":42,"name":"tester"}`))
		case "/api/server":
			_, _ = w.Write([]byte(`{"id":1}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(traccarServer.Close)

	cfg := &config.Config{
		TraccarWebhookSecret: secret,
		TraccarServerID:      1,
		DefaultLocale:        "zh",
		RateLimitPerMin:      60,
		AliasTTL:             time.Hour,
		IdempotencyTTL:       time.Hour,
		TraccarTimeout:       2 * time.Second,
	}
	storage := store.NewMemory(cfg.AliasTTL, cfg.IdempotencyTTL)
	client := jpush.New(jpush.Options{
		AppKey:       "app-key",
		MasterSecret: "master-secret",
		BaseURL:      jpushServer.URL,
	})
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelError}))
	service := gateway.New(cfg, storage, client, template.New(), auth.NewTraccarClient(traccarServer.URL, 2*time.Second), logger)

	mux := http.NewServeMux()
	NewServer(service, storage, "admin-token", logger).Register(mux)
	server := httptest.NewServer(mux)
	t.Cleanup(server.Close)
	return server
}

func eventBody() []byte {
	payload := map[string]any{
		"version":    1,
		"userId":     42,
		"deviceId":   7,
		"deviceName": "测试车",
		"event": map[string]any{
			"id":       555,
			"type":     "geofenceEnter",
			"deviceId": 7,
		},
	}
	encoded, _ := json.Marshal(payload)
	return encoded
}

func TestEventEndpoint(t *testing.T) {
	server := newTestServer(t)

	// 先注册别名。
	registerBody, _ := json.Marshal(map[string]any{
		"alias":    "u42@1",
		"platform": "android",
	})
	request, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/aliases", bytes.NewReader(registerBody))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer token-42")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("注册别名失败: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("注册别名状态码错误: %d", response.StatusCode)
	}

	body := eventBody()
	request, _ = http.NewRequest(http.MethodPost, server.URL+"/v1/events", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Traccar-Signature", auth.Sign(secret, body))
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("上报事件失败: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		payload, _ := io.ReadAll(response.Body)
		t.Fatalf("事件接口状态码错误: %d %s", response.StatusCode, payload)
	}
	var result map[string]any
	_ = json.NewDecoder(response.Body).Decode(&result)
	if result["status"] != gateway.StatusSent {
		t.Fatalf("事件状态错误: %v", result)
	}
}

func TestEventEndpointRejectsMissingSignature(t *testing.T) {
	server := newTestServer(t)
	request, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/events", bytes.NewReader(eventBody()))
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("缺少签名应当返回 401，实际 %d", response.StatusCode)
	}
}

func TestAliasEndpointRejectsForeignToken(t *testing.T) {
	server := newTestServer(t)
	body, _ := json.Marshal(map[string]any{"alias": "u7@1"})
	request, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/aliases", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer other-token")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("别名越权应当返回 401，实际 %d", response.StatusCode)
	}
}

func TestAdminEndpointsRequireToken(t *testing.T) {
	server := newTestServer(t)

	response, err := http.Get(server.URL + "/v1/aliases")
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("缺少管理员令牌应当返回 401，实际 %d", response.StatusCode)
	}

	request, _ := http.NewRequest(http.MethodGet, server.URL+"/v1/aliases", nil)
	request.Header.Set("Authorization", "Bearer admin-token")
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("管理员请求应当成功，实际 %d", response.StatusCode)
	}
}

func TestHealthEndpoints(t *testing.T) {
	server := newTestServer(t)
	for _, path := range []string{"/healthz", "/readyz"} {
		response, err := http.Get(server.URL + path)
		if err != nil {
			t.Fatalf("%s 请求失败: %v", path, err)
		}
		response.Body.Close()
		if response.StatusCode != http.StatusOK {
			t.Fatalf("%s 应当返回 200，实际 %d", path, response.StatusCode)
		}
	}
}

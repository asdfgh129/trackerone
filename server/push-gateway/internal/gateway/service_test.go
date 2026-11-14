package gateway

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/trackerone/push-gateway/internal/auth"
	"github.com/trackerone/push-gateway/internal/config"
	"github.com/trackerone/push-gateway/internal/jpush"
	"github.com/trackerone/push-gateway/internal/model"
	"github.com/trackerone/push-gateway/internal/store"
	"github.com/trackerone/push-gateway/internal/template"
)

const testSecret = "test-secret"

type jpushRecorder struct {
	mu    sync.Mutex
	hits  int
	calls []map[string]any
}

func (r *jpushRecorder) record(payload map[string]any) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.hits++
	r.calls = append(r.calls, payload)
}

type harness struct {
	service *Service
	storage *store.MemoryStore
	jpush   *jpushRecorder
}

func newHarness(t *testing.T, traccarURL string) *harness {
	t.Helper()

	recorder := &jpushRecorder{}
	jpushServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var payload map[string]any
		_ = json.Unmarshal(body, &payload)
		recorder.record(payload)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"sendno":"sn","msg_id":123456}`))
	}))
	t.Cleanup(jpushServer.Close)

	cfg := &config.Config{
		TraccarWebhookSecret: testSecret,
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

	service := New(cfg, storage, client, template.New(), auth.NewTraccarClient(traccarURL, 2*time.Second), logger)
	return &harness{service: service, storage: storage, jpush: recorder}
}

func traccarStub() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/session":
			_, _ = w.Write([]byte(`{"id":42,"name":"tester","email":"t@example.com"}`))
		case "/api/server":
			_, _ = w.Write([]byte(`{"id":1,"version":"6.16"}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
}

func eventPayload() []byte {
	payload := model.TraccarEvent{
		Version:    1,
		UserID:     42,
		UserEmail:  "t@example.com",
		DeviceID:   7,
		DeviceName: "京A·12345",
		Event: model.Event{
			ID:         555,
			DeviceID:   7,
			Type:       "geofenceEnter",
			GeofenceID: 9,
			Attributes: map[string]any{"geofenceName": "公司"},
		},
		Message: &model.Message{Title: "围栏进入", Body: "京A·12345 进入「公司」"},
	}
	encoded, _ := json.Marshal(payload)
	return encoded
}

func registerAlias(t *testing.T, h *harness, token string) {
	t.Helper()
	_, err := h.service.RegisterAlias(context.Background(), token, model.AliasRequest{
		Alias:       "u42@1",
		Platform:    "android",
		Vendor:      "xiaomi",
		AppVersion:  "0.4.0",
		DeviceModel: "Xiaomi 14",
	})
	if err != nil {
		t.Fatalf("注册别名失败: %v", err)
	}
}

func TestHandleEventSendsPush(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")

	body := eventPayload()
	result, err := h.service.HandleEvent(
		context.Background(),
		body,
		auth.Sign(testSecret, body),
		"zh",
	)
	if err != nil {
		t.Fatalf("处理事件失败: %v", err)
	}
	if result.Status != StatusSent {
		t.Fatalf("状态错误: %s", result.Status)
	}
	if h.jpush.hits != 1 {
		t.Fatalf("极光应被调用 1 次，实际 %d", h.jpush.hits)
	}
	if result.Alias != "u42@1" {
		t.Fatalf("别名错误: %s", result.Alias)
	}
	// extras 必须能透传 eventId，客户端据此跳转。
	payload := h.jpush.calls[0]
	notification := payload["notification"].(map[string]any)
	android := notification["android"].(map[string]any)
	extras := android["extras"].(map[string]any)
	if int64(extras["eventId"].(float64)) != 555 {
		t.Fatalf("extras.eventId 错误: %v", extras["eventId"])
	}
}

func TestHandleEventRejectsBadSignature(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")

	_, err := h.service.HandleEvent(context.Background(), eventPayload(), "sha256=deadbeef", "zh")
	if err == nil {
		t.Fatal("错误签名应当返回鉴权失败")
	}
	if h.jpush.hits != 0 {
		t.Fatal("错误签名不应触发推送")
	}
}

func TestHandleEventIsIdempotent(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")

	body := eventPayload()
	signature := auth.Sign(testSecret, body)

	first, _ := h.service.HandleEvent(context.Background(), body, signature, "zh")
	second, _ := h.service.HandleEvent(context.Background(), body, signature, "zh")

	if first.Status != StatusSent {
		t.Fatalf("首次投递状态错误: %s", first.Status)
	}
	if second.Status != StatusDuplicate {
		t.Fatalf("重复事件应被忽略，实际 %s", second.Status)
	}
	if h.jpush.hits != 1 {
		t.Fatalf("重复事件不应重复推送，实际调用 %d", h.jpush.hits)
	}
}

func TestHandleEventWithoutAlias(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)

	body := eventPayload()
	result, err := h.service.HandleEvent(context.Background(), body, auth.Sign(testSecret, body), "zh")
	if err != nil {
		t.Fatalf("处理事件失败: %v", err)
	}
	if result.Status != StatusNoAlias {
		t.Fatalf("未注册别名应返回 no_alias，实际 %s", result.Status)
	}
	if h.jpush.hits != 0 {
		t.Fatal("未注册别名不应触发推送")
	}
}

func TestRegisterAliasValidatesToken(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)

	// 别名里的 userId 与令牌用户不一致：必须拒绝。
	_, err := h.service.RegisterAlias(context.Background(), "token-42", model.AliasRequest{
		Alias: "u99@1",
	})
	if err == nil {
		t.Fatal("别名与令牌用户不一致时应当被拒绝")
	}
}

func TestUnregisterAlias(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")

	if err := h.service.UnregisterAlias(context.Background(), "token-42", "u42@1"); err != nil {
		t.Fatalf("解绑别名失败: %v", err)
	}
	_, found, _ := h.storage.GetAlias(context.Background(), "u42@1")
	if found {
		t.Fatal("别名应当已被删除")
	}
}

func TestRateLimitCoalescesEvents(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")
	h.service.cfg.RateLimitPerMin = 1
	h.service.cfg.RateLimitRequeueDelay = 0

	body := eventPayload()
	first, _ := h.service.HandleEvent(context.Background(), body, auth.Sign(testSecret, body), "zh")
	if first.Status != StatusSent {
		t.Fatalf("首条应发送: %s", first.Status)
	}

	second := model.TraccarEvent{UserID: 42, DeviceID: 7, DeviceName: "车",
		Event: model.Event{ID: 556, Type: "alarm"}}
	encoded, _ := json.Marshal(second)
	result, _ := h.service.HandleEvent(context.Background(), encoded, auth.Sign(testSecret, encoded), "zh")
	if result.Status != StatusCoalesced {
		t.Fatalf("超限事件应被合并，实际 %s", result.Status)
	}
	if h.jpush.hits != 1 {
		t.Fatalf("超限事件不应立即推送，实际调用 %d", h.jpush.hits)
	}
}

func TestFlushDeferredSendsMerged(t *testing.T) {
	traccar := traccarStub()
	defer traccar.Close()
	h := newHarness(t, traccar.URL)
	registerAlias(t, h, "token-42")
	h.service.cfg.RateLimitPerMin = 1
	h.service.cfg.RateLimitRequeueDelay = 0

	body := eventPayload()
	_, _ = h.service.HandleEvent(context.Background(), body, auth.Sign(testSecret, body), "zh")

	second := model.TraccarEvent{UserID: 42, DeviceID: 7, DeviceName: "车",
		Event: model.Event{ID: 556, Type: "alarm"}}
	encoded, _ := json.Marshal(second)
	_, _ = h.service.HandleEvent(context.Background(), encoded, auth.Sign(testSecret, encoded), "zh")

	sent, err := h.service.FlushDeferred(context.Background())
	if err != nil {
		t.Fatalf("投递延后队列失败: %v", err)
	}
	if sent != 1 {
		t.Fatalf("应投递 1 条合并消息，实际 %d", sent)
	}
	if h.jpush.hits != 2 {
		t.Fatalf("极光应被调用 2 次，实际 %d", h.jpush.hits)
	}
}

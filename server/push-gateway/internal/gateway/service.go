// Package gateway 实现推送网关的业务逻辑。
package gateway

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/trackerone/push-gateway/internal/auth"
	"github.com/trackerone/push-gateway/internal/config"
	"github.com/trackerone/push-gateway/internal/jpush"
	"github.com/trackerone/push-gateway/internal/model"
	"github.com/trackerone/push-gateway/internal/store"
	"github.com/trackerone/push-gateway/internal/template"
)

// ErrUnauthorized 表示鉴权失败。
var ErrUnauthorized = errors.New("鉴权失败")

// Service 是网关的核心业务对象。
type Service struct {
	cfg      *config.Config
	store    store.Store
	jpush    *jpush.Client
	renderer *template.Renderer
	traccar  *auth.TraccarClient
	log      *slog.Logger

	// serverIDCache 缓存 Traccar 服务端 id，避免每次注册都请求一次。
	serverIDCache map[string]int64
}

// New 创建业务服务。
func New(
	cfg *config.Config,
	storage store.Store,
	client *jpush.Client,
	renderer *template.Renderer,
	traccar *auth.TraccarClient,
	logger *slog.Logger,
) *Service {
	return &Service{
		cfg:           cfg,
		store:         storage,
		jpush:         client,
		renderer:      renderer,
		traccar:       traccar,
		log:           logger,
		serverIDCache: map[string]int64{},
	}
}

// EventResult 是事件处理的对外结果。
type EventResult struct {
	Status  string `json:"status"`
	EventID int64  `json:"eventId"`
	Alias   string `json:"alias,omitempty"`
	MsgID   string `json:"msgId,omitempty"`
	Reason  string `json:"reason,omitempty"`
	Error   string `json:"error,omitempty"`
}

// 处理状态取值。
const (
	StatusSent      = "sent"
	StatusCoalesced = "coalesced"
	StatusDeferred  = "deferred"
	StatusDuplicate = "duplicate"
	StatusNoAlias   = "no_alias"
	StatusSkipped   = "skipped"
	StatusFailed    = "failed"
)

// HandleEvent 处理一条 Traccar 事件。
//
// 流程：验签 → 幂等 → 别名校验 → 限流 / 免打扰 → 渲染文案 → 投递极光。
func (s *Service) HandleEvent(ctx context.Context, raw []byte, signature, locale string) (EventResult, error) {
	if err := auth.Verify(s.cfg.TraccarWebhookSecret, raw, signature); err != nil {
		return EventResult{Status: StatusSkipped, Reason: "signature_invalid"}, ErrUnauthorized
	}

	var event model.TraccarEvent
	if err := json.Unmarshal(raw, &event); err != nil {
		return EventResult{Status: StatusSkipped, Reason: "bad_payload"}, fmt.Errorf("解析事件失败: %w", err)
	}
	if event.Event.ID <= 0 {
		return EventResult{Status: StatusSkipped, Reason: "missing_event_id"}, fmt.Errorf("事件缺少 id")
	}

	result := EventResult{EventID: event.Event.ID}

	// 幂等：同一 event.id 只推送一次。
	fresh, err := s.store.MarkEvent(ctx, event.Event.ID, s.cfg.IdempotencyTTL)
	if err != nil {
		return result, fmt.Errorf("幂等检查失败: %w", err)
	}
	if !fresh {
		result.Status = StatusDuplicate
		s.log.Info("duplicate event skipped", "eventId", event.Event.ID)
		return result, nil
	}

	alias := auth.AliasFor(event.UserID, s.serverIDOf(event))
	record, found, err := s.store.GetAlias(ctx, alias)
	if err != nil {
		return result, fmt.Errorf("查询别名失败: %w", err)
	}
	if !found {
		result.Status = StatusNoAlias
		result.Alias = alias
		s.log.Warn("alias not registered, event dropped", "eventId", event.Event.ID, "alias", alias)
		return result, nil
	}
	result.Alias = alias

	// 事件归属校验：事件里的 userId 必须与别名一致，防止越权推送。
	if record.UserID > 0 && record.UserID != event.UserID {
		result.Status = StatusSkipped
		result.Reason = "alias_mismatch"
		s.log.Warn("alias mismatch", "eventId", event.Event.ID, "alias", alias)
		return result, nil
	}

	// 限流：超限则合并延后。
	allowed, err := s.store.AllowRequest(
		ctx,
		fmt.Sprintf("user:%d", event.UserID),
		s.cfg.RateLimitPerMin,
		time.Minute,
	)
	if err != nil {
		return result, fmt.Errorf("限流检查失败: %w", err)
	}
	if !allowed {
		delay := s.cfg.RateLimitRequeueDelay
		if err := s.deferEvent(ctx, event, "rate_limit", time.Now().Add(delay)); err != nil {
			return result, err
		}
		result.Status = StatusCoalesced
		result.Reason = "rate_limited"
		s.log.Warn("rate limited, event coalesced", "eventId", event.Event.ID, "alias", alias)
		return result, nil
	}

	// 免打扰时段只入库不推送。
	if until, quiet := s.quietUntil(time.Now()); quiet {
		if err := s.deferEvent(ctx, event, "quiet_hours", until); err != nil {
			return result, err
		}
		result.Status = StatusDeferred
		result.Reason = "quiet_hours"
		s.log.Info("quiet hours, event deferred", "eventId", event.Event.ID, "until", until)
		return result, nil
	}

	title, body := s.renderer.Render(event, s.locale(locale))
	pushResult, err := s.deliver(ctx, record, title, body, event)
	if err != nil {
		result.Status = StatusFailed
		result.Error = err.Error()
		s.log.Error("push failed", "eventId", event.Event.ID, "alias", alias, "error", err)
		return result, nil
	}
	result.Status = StatusSent
	result.MsgID = pushResult.MsgID
	s.log.Info(
		"push sent",
		"eventId", event.Event.ID,
		"alias", alias,
		"type", event.Event.Type,
		"msgId", pushResult.MsgID,
	)
	return result, nil
}

// RegisterAlias 注册推送别名。
//
// token 为客户端的 Traccar 会话令牌；网关会向 Traccar 校验它，
// 并要求别名中的 userId 与令牌对应的用户一致。
func (s *Service) RegisterAlias(ctx context.Context, token string, request model.AliasRequest) (model.Alias, error) {
	userID, serverID, err := auth.ParseAlias(request.Alias)
	if err != nil {
		return model.Alias{}, err
	}

	if s.traccar.Enabled() {
		user, err := s.traccar.Session(ctx, token)
		if err != nil {
			return model.Alias{}, fmt.Errorf("%w: %s", ErrUnauthorized, err)
		}
		if user.ID != userID {
			return model.Alias{}, fmt.Errorf("%w: 别名与令牌用户不一致", ErrUnauthorized)
		}
		actualServerID, err := s.traccarServerID(ctx, token)
		if err != nil {
			return model.Alias{}, fmt.Errorf("%w: %s", ErrUnauthorized, err)
		}
		if actualServerID != serverID {
			return model.Alias{}, fmt.Errorf("%w: 别名中的 serverId 与 Traccar 不一致", ErrUnauthorized)
		}
	} else if token == "" {
		return model.Alias{}, fmt.Errorf("%w: 缺少 Traccar Token", ErrUnauthorized)
	}

	alias := model.Alias{
		Alias:       request.Alias,
		UserID:      userID,
		ServerID:    serverID,
		Platform:    request.Platform,
		Vendor:      request.Vendor,
		AppVersion:  request.AppVersion,
		DeviceModel: request.DeviceModel,
		LastSeen:    time.Now(),
	}
	if err := s.store.PutAlias(ctx, alias); err != nil {
		return model.Alias{}, fmt.Errorf("保存别名失败: %w", err)
	}
	s.log.Info("alias registered", "alias", alias.Alias, "platform", alias.Platform, "vendor", alias.Vendor)
	return alias, nil
}

// UnregisterAlias 删除别名（退出登录 / 注销账号）。
func (s *Service) UnregisterAlias(ctx context.Context, token, alias string) error {
	if _, _, err := auth.ParseAlias(alias); err != nil {
		return err
	}
	if s.traccar.Enabled() {
		user, err := s.traccar.Session(ctx, token)
		if err != nil {
			return fmt.Errorf("%w: %s", ErrUnauthorized, err)
		}
		userID, _, _ := auth.ParseAlias(alias)
		if user.ID != userID {
			return fmt.Errorf("%w: 别名不属于当前令牌用户", ErrUnauthorized)
		}
	}
	if err := s.store.DeleteAlias(ctx, alias); err != nil {
		return fmt.Errorf("删除别名失败: %w", err)
	}
	s.log.Info("alias removed", "alias", alias)
	return nil
}

// FlushDeferred 投递延后队列中的事件（限流合并 / 免打扰）。
func (s *Service) FlushDeferred(ctx context.Context) (int, error) {
	items, err := s.store.TakeDeferred(ctx, time.Now(), 200)
	if err != nil {
		return 0, fmt.Errorf("读取延后队列失败: %w", err)
	}
	if len(items) == 0 {
		return 0, nil
	}

	grouped := map[string][]model.Deferred{}
	order := make([]string, 0, len(items))
	for _, item := range items {
		if _, ok := grouped[item.Alias]; !ok {
			order = append(order, item.Alias)
		}
		grouped[item.Alias] = append(grouped[item.Alias], item)
	}

	sent := 0
	for _, alias := range order {
		batch := grouped[alias]
		record, found, err := s.store.GetAlias(ctx, alias)
		if err != nil || !found {
			continue
		}
		last := batch[len(batch)-1]
		title, body := s.mergedText(len(batch), last)
		pushResult, err := s.deliverRaw(ctx, record, title, body, map[string]any{
			"eventId":   last.EventID,
			"merged":    len(batch),
			"eventIds":  eventIDs(batch),
			"deviceId":  0,
			"eventType": "coalesced",
		})
		if err != nil {
			s.log.Error("deferred push failed", "alias", alias, "count", len(batch), "error", err)
			continue
		}
		sent++
		s.log.Info("deferred push sent", "alias", alias, "count", len(batch), "msgId", pushResult.MsgID)
	}
	return sent, nil
}

func (s *Service) deliver(
	ctx context.Context,
	record model.Alias,
	title, body string,
	event model.TraccarEvent,
) (jpush.Result, error) {
	extras := map[string]any{
		"eventId":   event.Event.ID,
		"deviceId":  event.DeviceID,
		"eventType": event.Event.Type,
	}
	if event.Event.GeofenceID > 0 {
		extras["geofenceId"] = event.Event.GeofenceID
	}
	return s.deliverRaw(ctx, record, title, body, extras)
}

// deliverRaw 带重试地调用极光；超过重试上限写入死信。
func (s *Service) deliverRaw(
	ctx context.Context,
	record model.Alias,
	title, body string,
	extras map[string]any,
) (jpush.Result, error) {
	platforms := platformsOf(record.Platform)
	backoff := 500 * time.Millisecond
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {
		result, err := s.jpush.Push(ctx, record.Alias, platforms, title, body, extras)
		if err == nil {
			return result, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
		if attempt < 3 {
			select {
			case <-ctx.Done():
			case <-time.After(backoff):
			}
			backoff *= 2
		}
	}
	dead := model.DeadLetter{
		Alias:    record.Alias,
		EventID:  toInt64(extras["eventId"]),
		Title:    title,
		Body:     body,
		Error:    lastErr.Error(),
		Attempts: 3,
		FailedAt: time.Now(),
	}
	if err := s.store.PutDeadLetter(context.WithoutCancel(ctx), dead); err != nil {
		s.log.Error("写入死信失败", "alias", record.Alias, "error", err)
	}
	return jpush.Result{}, lastErr
}

func (s *Service) deferEvent(
	ctx context.Context,
	event model.TraccarEvent,
	reason string,
	earliest time.Time,
) error {
	title, body := s.renderer.Render(event, s.cfg.DefaultLocale)
	alias := auth.AliasFor(event.UserID, s.serverIDOf(event))
	item := model.Deferred{
		Alias:      alias,
		EventID:    event.Event.ID,
		Title:      title,
		Body:       body,
		Reason:     reason,
		EarliestAt: earliest,
		CreatedAt:  time.Now(),
	}
	return s.store.EnqueueDeferred(ctx, item)
}

// quietUntil 判断当前是否处于免打扰时段，并返回可投递时间。
func (s *Service) quietUntil(now time.Time) (time.Time, bool) {
	startMin, endMin, enabled, err := s.cfg.QuietWindow()
	if err != nil || !enabled {
		return time.Time{}, false
	}
	location := time.UTC
	if s.cfg.QuietHoursTZ != "" {
		if loaded, err := time.LoadLocation(s.cfg.QuietHoursTZ); err == nil {
			location = loaded
		}
	}
	local := now.In(location)
	current := local.Hour()*60 + local.Minute()
	if startMin == endMin {
		return time.Time{}, false
	}
	if startMin < endMin {
		if current >= startMin && current < endMin {
			return time.Date(local.Year(), local.Month(), local.Day(), endMin/60, endMin%60, 0, 0, location), true
		}
		return time.Time{}, false
	}
	// 跨零点，例如 22:00-07:00。
	if current >= startMin || current < endMin {
		until := local.Add(24 * time.Hour)
		if current < endMin {
			until = time.Date(local.Year(), local.Month(), local.Day(), endMin/60, endMin%60, 0, 0, location)
		}
		return until, true
	}
	return time.Time{}, false
}

func (s *Service) mergedText(count int, last model.Deferred) (string, string) {
	if count == 1 {
		return last.Title, last.Body
	}
	return "多条事件已合并", fmt.Sprintf("有 %d 条事件被合并，最后一条：%s", count, last.Body)
}

func (s *Service) locale(requested string) string {
	if strings.TrimSpace(requested) != "" {
		return requested
	}
	return s.cfg.DefaultLocale
}

// serverIDOf 返回事件所属 Traccar 实例的服务端 id。
//
// webhook 载荷里没有 serverId，按部署配置取默认值（通常为 1）。
func (s *Service) serverIDOf(event model.TraccarEvent) int64 {
	return s.cfg.TraccarServerID
}

// traccarServerID 通过 Traccar 查询服务端 id（带缓存）。
func (s *Service) traccarServerID(ctx context.Context, token string) (int64, error) {
	if s.cfg.TraccarServerID > 0 {
		return s.cfg.TraccarServerID, nil
	}
	if cached, ok := s.serverIDCache[token]; ok {
		return cached, nil
	}
	id, err := s.traccar.ServerID(ctx, token)
	if err != nil {
		return 0, err
	}
	s.serverIDCache[token] = id
	return id, nil
}

func platformsOf(platform string) []string {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "ios":
		return []string{"ios"}
	case "android":
		return []string{"android"}
	default:
		return []string{"android", "ios"}
	}
}

func eventIDs(items []model.Deferred) []int64 {
	ids := make([]int64, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.EventID)
	}
	return ids
}

func toInt64(value any) int64 {
	switch typed := value.(type) {
	case int64:
		return typed
	case int:
		return int64(typed)
	case float64:
		return int64(typed)
	default:
		return 0
	}
}

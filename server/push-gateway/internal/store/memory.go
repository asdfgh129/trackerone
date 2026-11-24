package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/trackerone/push-gateway/internal/model"
)

// MemoryStore 是单进程内存实现，用于本地联调与单元测试。
//
// 数据在重启后丢失：生产环境必须使用 Redis。
type MemoryStore struct {
	mu          sync.Mutex
	aliases     map[string]model.Alias
	events      map[string]time.Time
	windows     map[string]*rateWindow
	deferred    []model.Deferred
	deadLetters []model.DeadLetter
	messages    map[string]model.InboxMessage
	inbox       map[string][]string
	messageSeq  int64
	aliasTTL    time.Duration
	eventTTL    time.Duration
	now         func() time.Time
}

// maxInboxMessagesPerUser 限制单个用户/服务器保留的消息数，避免内存无限增长。
const maxInboxMessagesPerUser = 1000

type rateWindow struct {
	count int
	reset time.Time
}

// NewMemory 创建内存存储。
func NewMemory(aliasTTL, eventTTL time.Duration) *MemoryStore {
	return &MemoryStore{
		aliases:  map[string]model.Alias{},
		events:   map[string]time.Time{},
		windows:  map[string]*rateWindow{},
		messages: map[string]model.InboxMessage{},
		inbox:    map[string][]string{},
		aliasTTL: aliasTTL,
		eventTTL: eventTTL,
		now:      time.Now,
	}
}

// SetClock 允许测试注入固定时钟。
func (s *MemoryStore) SetClock(now func() time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.now = now
}

func (s *MemoryStore) PutAlias(ctx context.Context, alias model.Alias) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	alias.LastSeen = s.now()
	s.aliases[alias.Alias] = alias
	return nil
}

func (s *MemoryStore) GetAlias(ctx context.Context, alias string) (model.Alias, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	record, ok := s.aliases[alias]
	if !ok {
		return model.Alias{}, false, nil
	}
	if s.aliasTTL > 0 && s.now().Sub(record.LastSeen) > s.aliasTTL {
		delete(s.aliases, alias)
		return model.Alias{}, false, nil
	}
	return record, true, nil
}

func (s *MemoryStore) DeleteAlias(ctx context.Context, alias string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.aliases, alias)
	return nil
}

func (s *MemoryStore) ListAliases(ctx context.Context) ([]model.Alias, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	list := make([]model.Alias, 0, len(s.aliases))
	for _, alias := range s.aliases {
		list = append(list, alias)
	}
	return list, nil
}

func (s *MemoryStore) MarkEvent(ctx context.Context, eventID int64, ttl time.Duration) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := strconv.FormatInt(eventID, 10)
	if expiry, ok := s.events[key]; ok && s.now().Before(expiry) {
		return false, nil
	}
	if ttl <= 0 {
		ttl = s.eventTTL
	}
	s.events[key] = s.now().Add(ttl)
	return true, nil
}

func (s *MemoryStore) AllowRequest(ctx context.Context, key string, limit int, window time.Duration) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	current, ok := s.windows[key]
	if !ok || s.now().After(current.reset) {
		s.windows[key] = &rateWindow{count: 1, reset: s.now().Add(window)}
		return true, nil
	}
	if current.count >= limit {
		return false, nil
	}
	current.count++
	return true, nil
}

func (s *MemoryStore) EnqueueDeferred(ctx context.Context, item model.Deferred) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.deferred = append(s.deferred, item)
	return nil
}

func (s *MemoryStore) TakeDeferred(ctx context.Context, now time.Time, limit int) ([]model.Deferred, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	ready := make([]model.Deferred, 0, limit)
	remainder := make([]model.Deferred, 0, len(s.deferred))
	for _, item := range s.deferred {
		if len(ready) < limit && !item.EarliestAt.After(now) {
			ready = append(ready, item)
			continue
		}
		remainder = append(remainder, item)
	}
	s.deferred = remainder
	return ready, nil
}

func (s *MemoryStore) PutDeadLetter(ctx context.Context, item model.DeadLetter) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.deadLetters = append(s.deadLetters, item)
	if len(s.deadLetters) > 1000 {
		s.deadLetters = s.deadLetters[len(s.deadLetters)-1000:]
	}
	return nil
}

func (s *MemoryStore) ListDeadLetters(ctx context.Context, limit int) ([]model.DeadLetter, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if limit <= 0 || limit > len(s.deadLetters) {
		limit = len(s.deadLetters)
	}
	out := make([]model.DeadLetter, limit)
	copy(out, s.deadLetters[len(s.deadLetters)-limit:])
	return out, nil
}

func (s *MemoryStore) Ping(ctx context.Context) error {
	return nil
}

func (s *MemoryStore) Close() error {
	return nil
}

// EncodeJSON 是内部辅助函数，供 Redis 实现复用。
func EncodeJSON(value any) ([]byte, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return nil, fmt.Errorf("序列化失败: %w", err)
	}
	return data, nil
}

func inboxScope(userID, serverID int64) string {
	return fmt.Sprintf("%d:%d", userID, serverID)
}

func (s *MemoryStore) PutInboxMessage(ctx context.Context, message model.InboxMessage) (model.InboxMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.messageSeq++
	message.Seq = s.messageSeq
	if message.ID == "" {
		message.ID = fmt.Sprintf("msg_%d_%d", message.UserID, message.Seq)
	}
	if message.CreatedAt.IsZero() {
		message.CreatedAt = s.now()
	}
	s.messages[message.ID] = message
	scope := inboxScope(message.UserID, message.ServerID)
	ids := append(s.inbox[scope], message.ID)
	if len(ids) > maxInboxMessagesPerUser {
		drop := len(ids) - maxInboxMessagesPerUser
		for _, id := range ids[:drop] {
			delete(s.messages, id)
		}
		ids = ids[drop:]
	}
	s.inbox[scope] = ids
	return message, nil
}

func (s *MemoryStore) ListInboxMessages(ctx context.Context, userID, serverID, afterSeq int64, limit int) ([]model.InboxMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if limit <= 0 {
		limit = 50
	}
	scope := inboxScope(userID, serverID)
	ids := s.inbox[scope]
	now := s.now()
	result := make([]model.InboxMessage, 0, limit)
	for _, id := range ids {
		message, ok := s.messages[id]
		if !ok {
			continue
		}
		// 已撤回或已过期的消息不再下发给 App，但保留在索引里供审计。
		if message.RevokedAt != nil {
			continue
		}
		if message.ExpiresAt != nil && !now.Before(*message.ExpiresAt) {
			continue
		}
		if message.Seq <= afterSeq {
			continue
		}
		result = append(result, message)
	}
	if afterSeq == 0 && len(result) > limit {
		result = result[len(result)-limit:]
	} else if len(result) > limit {
		result = result[:limit]
	}
	return result, nil
}

func (s *MemoryStore) ListInboxAudit(ctx context.Context, userID, serverID, beforeSeq int64, limit int) ([]model.InboxMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if limit <= 0 {
		limit = 50
	}
	ids := s.inbox[inboxScope(userID, serverID)]
	result := make([]model.InboxMessage, 0, limit)
	for i := len(ids) - 1; i >= 0 && len(result) < limit; i-- {
		message, ok := s.messages[ids[i]]
		if !ok {
			continue
		}
		if beforeSeq > 0 && message.Seq >= beforeSeq {
			continue
		}
		result = append(result, message)
	}
	return result, nil
}

func (s *MemoryStore) GetInboxMessage(ctx context.Context, userID, serverID int64, id string) (model.InboxMessage, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	message, ok := s.messages[id]
	if !ok || message.UserID != userID || message.ServerID != serverID {
		return model.InboxMessage{}, false, nil
	}
	return message, true, nil
}

func (s *MemoryStore) AckInboxMessage(ctx context.Context, userID, serverID int64, id string, at time.Time) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	message, ok := s.messages[id]
	if !ok || message.UserID != userID || message.ServerID != serverID {
		return false, nil
	}
	stamp := at
	message.AckedAt = &stamp
	s.messages[id] = message
	return true, nil
}

func (s *MemoryStore) RevokeInboxMessage(ctx context.Context, userID, serverID int64, id string, at time.Time) (model.InboxMessage, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	message, ok := s.messages[id]
	if !ok || message.UserID != userID || message.ServerID != serverID {
		return model.InboxMessage{}, false, nil
	}
	stamp := at
	message.RevokedAt = &stamp
	s.messages[id] = message
	return message, true, nil
}

func (s *MemoryStore) UpdateInboxPush(ctx context.Context, userID, serverID int64, id, status string, attempts int, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	message, ok := s.messages[id]
	if !ok || message.UserID != userID || message.ServerID != serverID {
		return nil
	}
	stamp := at
	message.PushStatus = status
	message.PushAttempts = attempts
	if status == "sent" {
		message.PushedAt = &stamp
	}
	s.messages[id] = message
	return nil
}

func (s *MemoryStore) DeleteInboxMessages(ctx context.Context, userID, serverID int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	scope := inboxScope(userID, serverID)
	for _, id := range s.inbox[scope] {
		delete(s.messages, id)
	}
	delete(s.inbox, scope)
	return nil
}

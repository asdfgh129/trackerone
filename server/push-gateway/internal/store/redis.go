package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/trackerone/push-gateway/internal/model"
)

const (
	keyAliasPrefix = "push:alias:"
	keyAliasSet    = "push:aliases"
	keyEventPrefix = "push:event:"
	keyRatePrefix  = "push:rate:"
	keyDeferred    = "push:deferred"
	keyDeadLetter  = "push:dead"
	keyInboxSeq    = "push:inbox:seq"
	keyInboxItem   = "push:inbox:item:"
	keyInboxIndex  = "push:inbox:index:"
)

// RedisStore 是生产实现。
type RedisStore struct {
	client   *redis.Client
	aliasTTL time.Duration
}

// NewRedis 创建 Redis 存储。aliasTTL 为别名记录的存活时间。
func NewRedis(addr, password string, db int, aliasTTL time.Duration) *RedisStore {
	return &RedisStore{
		client: redis.NewClient(&redis.Options{
			Addr:         addr,
			Password:     password,
			DB:           db,
			DialTimeout:  5 * time.Second,
			ReadTimeout:  3 * time.Second,
			WriteTimeout: 3 * time.Second,
		}),
		aliasTTL: aliasTTL,
	}
}

func (s *RedisStore) PutAlias(ctx context.Context, alias model.Alias) error {
	alias.LastSeen = time.Now()
	payload, err := json.Marshal(alias)
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, keyAliasPrefix+alias.Alias, payload, s.aliasTTL)
	pipe.SAdd(ctx, keyAliasSet, alias.Alias)
	_, err = pipe.Exec(ctx)
	return err
}

func (s *RedisStore) GetAlias(ctx context.Context, alias string) (model.Alias, bool, error) {
	payload, err := s.client.Get(ctx, keyAliasPrefix+alias).Bytes()
	if errors.Is(err, redis.Nil) {
		return model.Alias{}, false, nil
	}
	if err != nil {
		return model.Alias{}, false, err
	}
	var record model.Alias
	if err := json.Unmarshal(payload, &record); err != nil {
		return model.Alias{}, false, err
	}
	return record, true, nil
}

func (s *RedisStore) DeleteAlias(ctx context.Context, alias string) error {
	pipe := s.client.TxPipeline()
	pipe.Del(ctx, keyAliasPrefix+alias)
	pipe.SRem(ctx, keyAliasSet, alias)
	_, err := pipe.Exec(ctx)
	return err
}

func (s *RedisStore) ListAliases(ctx context.Context) ([]model.Alias, error) {
	aliases, err := s.client.SMembers(ctx, keyAliasSet).Result()
	if err != nil {
		return nil, err
	}
	list := make([]model.Alias, 0, len(aliases))
	for _, alias := range aliases {
		record, ok, err := s.GetAlias(ctx, alias)
		if err != nil {
			continue
		}
		if ok {
			list = append(list, record)
		}
	}
	return list, nil
}

func (s *RedisStore) MarkEvent(ctx context.Context, eventID int64, ttl time.Duration) (bool, error) {
	created, err := s.client.SetNX(ctx, keyEventPrefix+strconv.FormatInt(eventID, 10), "1", ttl).Result()
	if err != nil {
		return false, err
	}
	return created, nil
}

func (s *RedisStore) AllowRequest(ctx context.Context, key string, limit int, window time.Duration) (bool, error) {
	redisKey := keyRatePrefix + key
	count, err := s.client.Incr(ctx, redisKey).Result()
	if err != nil {
		return false, err
	}
	if count == 1 {
		s.client.Expire(ctx, redisKey, window)
	}
	return int(count) <= limit, nil
}

func (s *RedisStore) EnqueueDeferred(ctx context.Context, item model.Deferred) error {
	payload, err := json.Marshal(item)
	if err != nil {
		return err
	}
	return s.client.LPush(ctx, keyDeferred, payload).Err()
}

func (s *RedisStore) TakeDeferred(ctx context.Context, now time.Time, limit int) ([]model.Deferred, error) {
	if limit <= 0 {
		limit = 100
	}
	items, err := s.client.LRange(ctx, keyDeferred, 0, int64(limit-1)).Result()
	if err != nil {
		return nil, err
	}
	ready := make([]model.Deferred, 0, len(items))
	remain := make([]string, 0, len(items))
	for _, raw := range items {
		var item model.Deferred
		if err := json.Unmarshal([]byte(raw), &item); err != nil {
			continue
		}
		if !item.EarliestAt.After(now) {
			ready = append(ready, item)
			continue
		}
		remain = append(remain, raw)
	}
	if len(remain) > 0 {
		pipe := s.client.TxPipeline()
		pipe.LTrim(ctx, keyDeferred, int64(len(remain)), -1)
		if _, err := pipe.Exec(ctx); err != nil {
			return ready, err
		}
	}
	return ready, nil
}

func (s *RedisStore) PutDeadLetter(ctx context.Context, item model.DeadLetter) error {
	payload, err := json.Marshal(item)
	if err != nil {
		return err
	}
	return s.client.LPush(ctx, keyDeadLetter, payload).Err()
}

func (s *RedisStore) ListDeadLetters(ctx context.Context, limit int) ([]model.DeadLetter, error) {
	if limit <= 0 {
		limit = 100
	}
	items, err := s.client.LRange(ctx, keyDeadLetter, 0, int64(limit-1)).Result()
	if err != nil {
		return nil, err
	}
	out := make([]model.DeadLetter, 0, len(items))
	for _, raw := range items {
		var item model.DeadLetter
		if err := json.Unmarshal([]byte(raw), &item); err != nil {
			continue
		}
		out = append(out, item)
	}
	return out, nil
}

func (s *RedisStore) Ping(ctx context.Context) error {
	if err := s.client.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("Redis 不可用: %w", err)
	}
	return nil
}

func (s *RedisStore) Close() error {
	return s.client.Close()
}

func inboxIndexKey(userID, serverID int64) string {
	return keyInboxIndex + strconv.FormatInt(userID, 10) + ":" + strconv.FormatInt(serverID, 10)
}

func inboxItemKey(id string) string {
	return keyInboxItem + id
}

func (s *RedisStore) PutInboxMessage(ctx context.Context, message model.InboxMessage) (model.InboxMessage, error) {
	seq, err := s.client.Incr(ctx, keyInboxSeq).Result()
	if err != nil {
		return model.InboxMessage{}, err
	}
	message.Seq = seq
	if message.ID == "" {
		message.ID = fmt.Sprintf("msg_%d_%d", message.UserID, seq)
	}
	if message.CreatedAt.IsZero() {
		message.CreatedAt = time.Now()
	}
	ttl := 7 * 24 * time.Hour
	if message.ExpiresAt != nil {
		ttl = time.Until(*message.ExpiresAt)
		if ttl <= 0 {
			ttl = time.Minute
		}
	}
	payload, err := json.Marshal(message)
	if err != nil {
		return model.InboxMessage{}, err
	}
	index := inboxIndexKey(message.UserID, message.ServerID)
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, inboxItemKey(message.ID), payload, ttl)
	pipe.ZAdd(ctx, index, redis.Z{Score: float64(seq), Member: message.ID})
	// 仅保留最近 maxInboxMessagesPerUser 条；更早条目的 item key 依赖 TTL 回收。
	pipe.ZRemRangeByRank(ctx, index, 0, -maxInboxMessagesPerUser-1)
	if _, err := pipe.Exec(ctx); err != nil {
		return model.InboxMessage{}, err
	}
	return message, nil
}

func (s *RedisStore) ListInboxMessages(ctx context.Context, userID, serverID, afterSeq int64, limit int) ([]model.InboxMessage, error) {
	if limit <= 0 {
		limit = 50
	}
	index := inboxIndexKey(userID, serverID)
	var ids []string
	var err error
	if afterSeq > 0 {
		ids, err = s.client.ZRangeByScore(ctx, index, &redis.ZRangeBy{
			Min:    "(" + strconv.FormatInt(afterSeq, 10),
			Max:    "+inf",
			Offset: 0,
			Count:  int64(limit),
		}).Result()
	} else {
		ids, err = s.client.ZRevRange(ctx, index, 0, int64(limit-1)).Result()
		if err == nil {
			// 统一成升序，游标取最后一条。
			for left, right := 0, len(ids)-1; left < right; left, right = left+1, right-1 {
				ids[left], ids[right] = ids[right], ids[left]
			}
		}
	}
	if err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return []model.InboxMessage{}, nil
	}

	keys := make([]string, len(ids))
	for i, id := range ids {
		keys[i] = inboxItemKey(id)
	}
	values, err := s.client.MGet(ctx, keys...).Result()
	if err != nil {
		return nil, err
	}
	now := time.Now()
	result := make([]model.InboxMessage, 0, len(values))
	expired := make([]any, 0)
	for i, value := range values {
		raw, ok := value.(string)
		if !ok {
			continue
		}
		var message model.InboxMessage
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			continue
		}
		if message.ExpiresAt != nil && !now.Before(*message.ExpiresAt) {
			expired = append(expired, ids[i])
			continue
		}
		result = append(result, message)
	}
	if len(expired) > 0 {
		// 清理已过期条目的索引，避免游标空洞。
		_ = s.client.ZRem(ctx, index, expired...).Err()
	}
	return result, nil
}

func (s *RedisStore) AckInboxMessage(ctx context.Context, userID, serverID int64, id string, at time.Time) (bool, error) {
	key := inboxItemKey(id)
	payload, err := s.client.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var message model.InboxMessage
	if err := json.Unmarshal(payload, &message); err != nil {
		return false, nil
	}
	if message.UserID != userID || message.ServerID != serverID {
		return false, nil
	}
	if message.ExpiresAt != nil && !time.Now().Before(*message.ExpiresAt) {
		return false, nil
	}
	stamp := at
	message.AckedAt = &stamp
	encoded, err := json.Marshal(message)
	if err != nil {
		return false, err
	}
	if err := s.client.SetArgs(ctx, key, encoded, redis.SetArgs{KeepTTL: true}).Err(); err != nil {
		return false, err
	}
	return true, nil
}

func (s *RedisStore) DeleteInboxMessages(ctx context.Context, userID, serverID int64) error {
	index := inboxIndexKey(userID, serverID)
	ids, err := s.client.ZRange(ctx, index, 0, -1).Result()
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	if len(ids) > 0 {
		keys := make([]string, len(ids))
		for i, id := range ids {
			keys[i] = inboxItemKey(id)
		}
		pipe.Del(ctx, keys...)
	}
	pipe.Del(ctx, index)
	_, err = pipe.Exec(ctx)
	return err
}

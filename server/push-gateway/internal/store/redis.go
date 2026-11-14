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

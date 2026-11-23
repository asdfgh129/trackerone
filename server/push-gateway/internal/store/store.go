// Package store 定义网关需要的持久化能力，并提供 Redis 与内存两种实现。
package store

import (
	"context"
	"time"

	"github.com/trackerone/push-gateway/internal/model"
)

// Store 是网关的存储抽象。
//
// 别名、幂等键、限流计数、延后队列与死信全部通过它读写，
// 便于在单机开发时切换到内存实现（STORE_BACKEND=memory）。
type Store interface {
	// PutAlias 保存或刷新别名记录。
	PutAlias(ctx context.Context, alias model.Alias) error
	// GetAlias 查询别名。
	GetAlias(ctx context.Context, alias string) (model.Alias, bool, error)
	// DeleteAlias 删除别名（退出登录 / 注销账号）。
	DeleteAlias(ctx context.Context, alias string) error
	// ListAliases 列出全部别名，供延后队列的 flush 使用。
	ListAliases(ctx context.Context) ([]model.Alias, error)

	// MarkEvent 记录事件 id；返回 true 表示首次出现（未重复）。
	MarkEvent(ctx context.Context, eventID int64, ttl time.Duration) (bool, error)

	// AllowRequest 限流：窗口内未超过 limit 时返回 true。
	AllowRequest(ctx context.Context, key string, limit int, window time.Duration) (bool, error)

	// EnqueueDeferred 将事件放入延后队列（限流合并 / 免打扰）。
	EnqueueDeferred(ctx context.Context, item model.Deferred) error
	// TakeDeferred 取出到期的延后事件，最多 limit 条。
	TakeDeferred(ctx context.Context, now time.Time, limit int) ([]model.Deferred, error)

	// PutInboxMessage 保存一条收件箱消息，分配序号与 id。
	PutInboxMessage(ctx context.Context, message model.InboxMessage) (model.InboxMessage, error)
	// ListInboxMessages 返回序号大于 afterSeq 的消息（按序号升序），最多 limit 条。
	// afterSeq 为 0 时返回最新一页。
	ListInboxMessages(ctx context.Context, userID, serverID, afterSeq int64, limit int) ([]model.InboxMessage, error)
	// AckInboxMessage 记录投递回执；消息不属于该用户时返回 false。
	AckInboxMessage(ctx context.Context, userID, serverID int64, id string, at time.Time) (bool, error)
	// DeleteInboxMessages 删除某用户在某服务器上的全部消息（注销 / 清除数据）。
	DeleteInboxMessages(ctx context.Context, userID, serverID int64) error

	// PutDeadLetter 记录投递失败的死信。
	PutDeadLetter(ctx context.Context, item model.DeadLetter) error
	// ListDeadLetters 列出死信。
	ListDeadLetters(ctx context.Context, limit int) ([]model.DeadLetter, error)

	// Ping 用于就绪检查。
	Ping(ctx context.Context) error
	// Close 释放资源。
	Close() error
}

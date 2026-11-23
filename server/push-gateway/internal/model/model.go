// Package model 定义 Traccar webhook 推送的事件与别名数据结构。
//
// 契约见仓库根目录 server/README.md（第 2 节）。
package model

import "time"

// TraccarEvent 是 NotificatorWebhook 推送到网关的事件体。
type TraccarEvent struct {
	Version    int       `json:"version"`
	UserID     int64     `json:"userId"`
	UserEmail  string    `json:"userEmail"`
	DeviceID   int64     `json:"deviceId"`
	DeviceName string    `json:"deviceName"`
	UniqueID   string    `json:"uniqueId"`
	Event      Event     `json:"event"`
	Position   *Position `json:"position,omitempty"`
	Message    *Message  `json:"message,omitempty"`
	IssuedAt   int64     `json:"issuedAt"`
}

// Event 是 Traccar 事件本体。
type Event struct {
	ID         int64          `json:"id"`
	DeviceID   int64          `json:"deviceId"`
	Type       string         `json:"type"`
	EventTime  string         `json:"eventTime"`
	PositionID int64          `json:"positionId"`
	GeofenceID int64          `json:"geofenceId"`
	Attributes map[string]any `json:"attributes"`
}

// Position 是事件发生时的位置快照。
type Position struct {
	ID         int64          `json:"id"`
	DeviceID   int64          `json:"deviceId"`
	Latitude   float64        `json:"latitude"`
	Longitude  float64        `json:"longitude"`
	FixTime    string         `json:"fixTime"`
	Attributes map[string]any `json:"attributes"`
}

// Message 是服务端渲染好的通知文案，网关会在多语言模板缺失时回退使用。
type Message struct {
	Title  string `json:"title"`
	Body   string `json:"body"`
	Digest string `json:"digest"`
}

// AliasRequest 是客户端注册推送别名的请求体。
type AliasRequest struct {
	Alias       string `json:"alias"`
	Platform    string `json:"platform"`
	Vendor      string `json:"vendor"`
	AppVersion  string `json:"appVersion"`
	DeviceModel string `json:"deviceModel"`
}

// Alias 是网关保存的别名记录。
type Alias struct {
	Alias       string    `json:"alias"`
	UserID      int64     `json:"userId"`
	ServerID    int64     `json:"serverId"`
	Platform    string    `json:"platform"`
	Vendor      string    `json:"vendor"`
	AppVersion  string    `json:"appVersion"`
	DeviceModel string    `json:"deviceModel"`
	LastSeen    time.Time `json:"lastSeen"`
}

// Deferred 是一条被延后投递的事件（限流合并或免打扰时段）。
type Deferred struct {
	Alias      string    `json:"alias"`
	EventID    int64     `json:"eventId"`
	Title      string    `json:"title"`
	Body       string    `json:"body"`
	Reason     string    `json:"reason"`
	EarliestAt time.Time `json:"earliestAt"`
	CreatedAt  time.Time `json:"createdAt"`
}

// DeadLetter 是投递失败超过重试上限的事件。
type DeadLetter struct {
	Alias    string    `json:"alias"`
	EventID  int64     `json:"eventId"`
	Title    string    `json:"title"`
	Body     string    `json:"body"`
	Error    string    `json:"error"`
	Attempts int       `json:"attempts"`
	FailedAt time.Time `json:"failedAt"`
}

// InboxMessage 是服务端下发给 App 用户的消息（收件箱契约见 docs/17）。
//
// Seq 是网关内部单调递增序号，用作增量游标；对外只暴露 id。
type InboxMessage struct {
	ID        string         `json:"id"`
	Seq       int64          `json:"-"`
	UserID    int64          `json:"-"`
	ServerID  int64          `json:"-"`
	Kind      string         `json:"kind"`
	Title     string         `json:"title,omitempty"`
	Body      string         `json:"body,omitempty"`
	Data      map[string]any `json:"data,omitempty"`
	CreatedAt time.Time      `json:"createdAt"`
	ExpiresAt *time.Time     `json:"expiresAt,omitempty"`
	AckedAt   *time.Time     `json:"-"`
}

// InboxSendRequest 是管理端写入一条收件箱消息的请求体。
//
// ExpiresIn 单位为秒；为 0 时按 kind 取默认 TTL（command 1h / notice 7d / chat 3d）。
type InboxSendRequest struct {
	UserID    int64          `json:"userId"`
	ServerID  int64          `json:"serverId,omitempty"`
	Kind      string         `json:"kind"`
	Title     string         `json:"title"`
	Body      string         `json:"body"`
	Data      map[string]any `json:"data,omitempty"`
	ExpiresIn int64          `json:"expiresIn,omitempty"`
}

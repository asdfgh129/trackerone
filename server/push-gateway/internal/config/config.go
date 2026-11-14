// Package config 负责读取并校验网关运行所需的环境变量。
//
// 所有敏感项（Traccar webhook secret、极光 Master Secret）只从环境变量读取，
// 不落配置文件、不进日志。
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config 是网关的运行期配置。
type Config struct {
	ListenAddr string

	// Traccar 侧
	TraccarBaseURL       string
	TraccarWebhookSecret string
	TraccarTimeout       time.Duration
	TraccarServerID      int64
	DefaultLocale        string

	// 极光侧
	JPushAppKey         string
	JPushMasterSecret   string
	JPushAPIBase        string
	JPushTTL            int
	JPushAPNSProduction bool
	JPushChannel        string

	// 存储
	RedisAddr     string
	RedisPassword string
	RedisDB       int
	StoreBackend  string // redis | memory

	AliasTTL        time.Duration
	IdempotencyTTL  time.Duration
	RateLimitPerMin int

	// RateLimitRequeueDelay 是限流合并后多久重新投递。
	RateLimitRequeueDelay time.Duration

	// 免打扰
	QuietHours   string
	QuietHoursTZ string

	AdminToken string
	DryRun     bool
	LogLevel   string

	FlushInterval       time.Duration
	MaxDeferredPerAlias int
}

// Load 从环境变量构建配置，并对必填项做校验。
func Load() (*Config, error) {
	cfg := &Config{
		ListenAddr:            env("LISTEN_ADDR", ":8080"),
		TraccarBaseURL:        strings.TrimRight(env("TRACCAR_BASE_URL", ""), "/"),
		TraccarWebhookSecret:  env("TRACCAR_WEBHOOK_SECRET", ""),
		TraccarTimeout:        envDuration("TRACCAR_TIMEOUT", 5*time.Second),
		TraccarServerID:       int64(envInt("TRACCAR_SERVER_ID", 1)),
		DefaultLocale:         env("DEFAULT_LOCALE", "zh"),
		JPushAppKey:           env("JPUSH_APP_KEY", ""),
		JPushMasterSecret:     env("JPUSH_MASTER_SECRET", ""),
		JPushAPIBase:          strings.TrimRight(env("JPUSH_API_BASE", "https://api.jpush.cn"), "/"),
		JPushTTL:              envInt("JPUSH_TTL", 3600),
		JPushAPNSProduction:   envBool("JPUSH_APNS_PRODUCTION", true),
		JPushChannel:          env("JPUSH_CHANNEL", "developer-default"),
		RedisAddr:             env("REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword:         env("REDIS_PASSWORD", ""),
		RedisDB:               envInt("REDIS_DB", 0),
		StoreBackend:          env("STORE_BACKEND", "redis"),
		AliasTTL:              envDuration("ALIAS_TTL", 90*24*time.Hour),
		IdempotencyTTL:        envDuration("IDEMPOTENCY_TTL", 24*time.Hour),
		RateLimitPerMin:       envInt("RATE_LIMIT_PER_MINUTE", 60),
		RateLimitRequeueDelay: envDuration("RATE_LIMIT_REQUEUE_DELAY", time.Minute),
		QuietHours:            env("QUIET_HOURS", ""),
		QuietHoursTZ:          env("QUIET_HOURS_TZ", "Asia/Shanghai"),
		AdminToken:            env("ADMIN_TOKEN", ""),
		DryRun:                envBool("DRY_RUN", false),
		LogLevel:              env("LOG_LEVEL", "info"),
		FlushInterval:         envDuration("FLUSH_INTERVAL", time.Minute),
		MaxDeferredPerAlias:   envInt("MAX_DEFERRED_PER_ALIAS", 20),
	}

	if cfg.TraccarWebhookSecret == "" {
		return nil, fmt.Errorf("TRACCAR_WEBHOOK_SECRET 未设置")
	}
	switch cfg.StoreBackend {
	case "redis", "memory":
	default:
		return nil, fmt.Errorf("STORE_BACKEND 只支持 redis / memory，当前为 %q", cfg.StoreBackend)
	}
	if !cfg.DryRun {
		if cfg.JPushAppKey == "" || cfg.JPushMasterSecret == "" {
			return nil, fmt.Errorf("JPUSH_APP_KEY / JPUSH_MASTER_SECRET 未设置（或使用 DRY_RUN=true）")
		}
	}
	if cfg.QuietHours != "" {
		if _, _, err := parseQuietHours(cfg.QuietHours); err != nil {
			return nil, fmt.Errorf("QUIET_HOURS 无效: %w", err)
		}
	}
	return cfg, nil
}

// QuietWindow 返回免打扰时间段（本地时区的起止分钟）。
func (c *Config) QuietWindow() (startMin, endMin int, enabled bool, err error) {
	if c.QuietHours == "" {
		return 0, 0, false, nil
	}
	startMin, endMin, err = parseQuietHours(c.QuietHours)
	if err != nil {
		return 0, 0, false, err
	}
	return startMin, endMin, true, nil
}

func parseQuietHours(value string) (int, int, error) {
	parts := strings.Split(strings.TrimSpace(value), "-")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("格式应为 HH:MM-HH:MM")
	}
	start, err := parseMinute(parts[0])
	if err != nil {
		return 0, 0, err
	}
	end, err := parseMinute(parts[1])
	if err != nil {
		return 0, 0, err
	}
	return start, end, nil
}

func parseMinute(value string) (int, error) {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) != 2 {
		return 0, fmt.Errorf("时间格式应为 HH:MM")
	}
	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return 0, fmt.Errorf("小时非法: %q", parts[0])
	}
	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return 0, fmt.Errorf("分钟非法: %q", parts[1])
	}
	return hour*60 + minute, nil
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	value, ok := os.LookupEnv(key)
	if !ok || value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envBool(key string, fallback bool) bool {
	value, ok := os.LookupEnv(key)
	if !ok || value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envDuration(key string, fallback time.Duration) time.Duration {
	value, ok := os.LookupEnv(key)
	if !ok || value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

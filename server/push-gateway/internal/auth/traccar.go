package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// TraccarClient 用于校验客户端带来的 Traccar Token。
//
// 网关不接受客户端自报的用户身份：必须用 Token 调 Traccar `/api/session`
// 换取真实用户 id，再据此推导别名，避免越权绑定他人 alias。
type TraccarClient struct {
	baseURL string
	client  *http.Client
}

// NewTraccarClient 创建 Traccar 客户端。baseURL 为空时禁用 Token 校验
// （仅允许本地联调使用）。
func NewTraccarClient(baseURL string, timeout time.Duration) *TraccarClient {
	return &TraccarClient{
		baseURL: baseURL,
		client:  &http.Client{Timeout: timeout},
	}
}

// Enabled 返回是否配置了 Traccar 地址。
func (c *TraccarClient) Enabled() bool {
	return c.baseURL != ""
}

// Session 用 Token 换取当前登录用户。
func (c *TraccarClient) Session(ctx context.Context, token string) (TraccarUser, error) {
	if !c.Enabled() {
		return TraccarUser{}, fmt.Errorf("TRACCAR_BASE_URL 未配置，无法校验 Token")
	}
	body, err := c.get(ctx, "/api/session", token)
	if err != nil {
		return TraccarUser{}, err
	}
	var user TraccarUser
	if err := json.Unmarshal(body, &user); err != nil {
		return TraccarUser{}, fmt.Errorf("解析 /api/session 失败: %w", err)
	}
	if user.ID <= 0 {
		return TraccarUser{}, fmt.Errorf("/api/session 未返回用户 id")
	}
	return user, nil
}

// ServerID 返回 Traccar 服务端 id（`/api/server` 的 id 字段，通常为 1）。
func (c *TraccarClient) ServerID(ctx context.Context, token string) (int64, error) {
	if !c.Enabled() {
		return 0, fmt.Errorf("TRACCAR_BASE_URL 未配置，无法获取服务端 id")
	}
	body, err := c.get(ctx, "/api/server", token)
	if err != nil {
		return 0, err
	}
	var payload struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return 0, fmt.Errorf("解析 /api/server 失败: %w", err)
	}
	if payload.ID <= 0 {
		return 0, fmt.Errorf("/api/server 未返回服务端 id")
	}
	return payload.ID, nil
}

func (c *TraccarClient) get(ctx context.Context, path, token string) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	response, err := c.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("请求 Traccar 失败: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return nil, fmt.Errorf("Token 无效（Traccar 返回 %d）", response.StatusCode)
	}
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Traccar 返回 %d", response.StatusCode)
	}
	return io.ReadAll(io.LimitReader(response.Body, 1<<20))
}

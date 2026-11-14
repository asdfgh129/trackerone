// Package auth 负责 Traccar → 网关 的 HMAC 校验，以及网关 → Traccar 的令牌校验。
package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

var (
	// ErrSignatureMissing 表示请求没有带签名头。
	ErrSignatureMissing = errors.New("缺少 X-Traccar-Signature")
	// ErrSignatureInvalid 表示签名不匹配。
	ErrSignatureInvalid = errors.New("签名校验失败")
)

// Sign 返回 `sha256=<hex>` 形式的签名，供测试与联调脚本使用。
func Sign(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

// Verify 校验 Traccar webhook 的 HMAC 签名。
//
// 允许两种写法：`sha256=<hex>`（插件默认）与裸 hex（curl 手工联调）。
// 比较使用 hmac.Equal，避免时序侧信道。
func Verify(secret string, body []byte, header string) error {
	if header == "" {
		return ErrSignatureMissing
	}
	expected := Sign(secret, body)
	provided := strings.TrimSpace(header)
	if !strings.Contains(provided, "=") {
		provided = "sha256=" + provided
	}
	if !hmac.Equal([]byte(expected), []byte(provided)) {
		return ErrSignatureInvalid
	}
	return nil
}

// TraccarUser 是 Traccar `/api/session` 返回的用户主体。
type TraccarUser struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

// AliasFor 按客户端约定生成别名：`u{userId}@{serverId}`。
func AliasFor(userID, serverID int64) string {
	return fmt.Sprintf("u%d@%d", userID, serverID)
}

// ParseAlias 解析别名并校验格式，格式非法时返回错误。
//
// 别名格式：`u{userId}@{serverId}`，与客户端 `PushService.aliasFor` 保持一致。
func ParseAlias(alias string) (userID, serverID int64, err error) {
	at := strings.Index(alias, "@")
	if at <= 0 || at == len(alias)-1 {
		return 0, 0, fmt.Errorf("别名格式应为 u{userId}@{serverId}: %q", alias)
	}
	userPart := alias[:at]
	if strings.HasPrefix(userPart, "u") {
		userPart = userPart[1:]
	}
	userID, err = parseInt(userPart, "userId")
	if err != nil {
		return 0, 0, err
	}
	serverID, err = parseInt(alias[at+1:], "serverId")
	if err != nil {
		return 0, 0, err
	}
	return userID, serverID, nil
}

func parseInt(value, field string) (int64, error) {
	var parsed int64
	if _, err := fmt.Sscanf(value, "%d", &parsed); err != nil {
		return 0, fmt.Errorf("%s 非法: %q", field, value)
	}
	if parsed <= 0 {
		return 0, fmt.Errorf("%s 必须为正整数: %q", field, value)
	}
	return parsed, nil
}

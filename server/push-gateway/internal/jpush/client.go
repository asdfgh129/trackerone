// Package jpush 是极光 JPush REST v3 客户端。
//
// 官方文档：https://docs.jpush.cn/
package jpush

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/trackerone/push-gateway/internal/model"
)

// Client 是极光推送客户端。
type Client struct {
	appKey         string
	masterSecret   string
	baseURL        string
	channel        string
	ttl            int
	apnsProduction bool
	dryRun         bool
	http           *http.Client
}

// Options 是构造参数。
type Options struct {
	AppKey         string
	MasterSecret   string
	BaseURL        string
	Channel        string
	TTL            int
	APNSProduction bool
	DryRun         bool
	Timeout        time.Duration
}

// New 创建极光客户端。
func New(options Options) *Client {
	if options.BaseURL == "" {
		options.BaseURL = "https://api.jpush.cn"
	}
	if options.TTL <= 0 {
		options.TTL = 3600
	}
	if options.Timeout <= 0 {
		options.Timeout = 10 * time.Second
	}
	return &Client{
		appKey:         options.AppKey,
		masterSecret:   options.MasterSecret,
		baseURL:        strings.TrimRight(options.BaseURL, "/"),
		channel:        options.Channel,
		ttl:            options.TTL,
		apnsProduction: options.APNSProduction,
		dryRun:         options.DryRun,
		http:           &http.Client{Timeout: options.Timeout},
	}
}

// Result 是一次投递的结果。
type Result struct {
	MsgID  string `json:"msgId"`
	SendNo string `json:"sendNo"`
}

// Push 按 alias 投递一条通知。
//
// extras 会原样透传到客户端，客户端据此做点击跳转与远程指令。
func (c *Client) Push(
	ctx context.Context,
	alias string,
	platforms []string,
	title string,
	body string,
	extras map[string]any,
) (Result, error) {
	if alias == "" {
		return Result{}, fmt.Errorf("alias 不能为空")
	}
	if len(platforms) == 0 {
		platforms = []string{"android", "ios"}
	}
	payload := map[string]any{
		"platform": platforms,
		"audience": map[string]any{"alias": []string{alias}},
		"notification": map[string]any{
			"android": map[string]any{
				"alert":  body,
				"title":  title,
				"extras": extras,
			},
			"ios": map[string]any{
				"alert":  map[string]any{"title": title, "body": body},
				"sound":  "default",
				"extras": extras,
			},
		},
		"options": map[string]any{
			"time_to_live":     c.ttl,
			"apns_production":  c.apnsProduction,
			"channel":          c.channel,
			"notify_by_aliyun": false,
		},
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return Result{}, fmt.Errorf("序列化推送体失败: %w", err)
	}

	if c.dryRun {
		// DRY_RUN：不真正调用极光，只把请求体打出来，便于本地联调。
		return Result{MsgID: "dry-run", SendNo: "dry-run"}, nil
	}

	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		c.baseURL+"/v3/push",
		bytes.NewReader(encoded),
	)
	if err != nil {
		return Result{}, err
	}
	request.Header.Set("Content-Type", "application/json")
	credential := base64.StdEncoding.EncodeToString([]byte(c.appKey + ":" + c.masterSecret))
	request.Header.Set("Authorization", "Basic "+credential)

	response, err := c.http.Do(request)
	if err != nil {
		return Result{}, fmt.Errorf("调用极光失败: %w", err)
	}
	defer response.Body.Close()
	bodyBytes, _ := io.ReadAll(io.LimitReader(response.Body, 1<<20))

	if response.StatusCode != http.StatusOK {
		return Result{}, fmt.Errorf("极光返回 %d: %s", response.StatusCode, truncate(string(bodyBytes), 300))
	}
	var raw map[string]any
	if err := json.Unmarshal(bodyBytes, &raw); err != nil {
		return Result{}, fmt.Errorf("解析极光响应失败: %w", err)
	}
	result := Result{}
	if value, ok := raw["sendno"]; ok {
		result.SendNo = fmt.Sprintf("%v", value)
	}
	if value, ok := raw["msg_id"]; ok {
		// 极光的 msg_id 可能是数字或字符串，统一转成字符串。
		result.MsgID = fmt.Sprintf("%v", value)
	}
	return result, nil
}

// PushEvent 是把事件渲染成通知后投递的便捷方法。
func (c *Client) PushEvent(
	ctx context.Context,
	alias string,
	platforms []string,
	title string,
	body string,
	event model.TraccarEvent,
) (Result, error) {
	extras := map[string]any{
		"eventId":   event.Event.ID,
		"deviceId":  event.DeviceID,
		"eventType": event.Event.Type,
	}
	if event.Event.GeofenceID > 0 {
		extras["geofenceId"] = event.Event.GeofenceID
	}
	return c.Push(ctx, alias, platforms, title, body, extras)
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "..."
}

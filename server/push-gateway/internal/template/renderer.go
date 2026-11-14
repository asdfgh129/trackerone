// Package template 负责把 Traccar 事件渲染成通知文案。
//
// 模板里可以用 {{device}} / {{eventType}} / {{geofence}} / {{speed}} /
// {{battery}} / {{value}} 等占位符。
package template

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/trackerone/push-gateway/internal/model"
)

// Template 是一条文案模板。
type Template struct {
	Title string
	Body  string
}

// Renderer 按语言渲染文案。
type Renderer struct {
	templates map[string]map[string]Template // locale -> eventType -> template
	fallback  map[string]Template
}

// New 创建渲染器，内置中英文模板。
func New() *Renderer {
	renderer := &Renderer{
		templates: map[string]map[string]Template{},
	}
	renderer.templates["zh"] = map[string]Template{
		"geofenceEnter":  {Title: "围栏进入", Body: "{{device}} 进入围栏「{{geofence}}」"},
		"geofenceExit":   {Title: "围栏离开", Body: "{{device}} 离开围栏「{{geofence}}」"},
		"alarm":          {Title: "告警", Body: "{{device}} 触发告警"},
		"ignitionOn":     {Title: "点火", Body: "{{device}} 已点火"},
		"ignitionOff":    {Title: "熄火", Body: "{{device}} 已熄火"},
		"speeding":       {Title: "超速", Body: "{{device}} 超速，速度 {{speed}} km/h"},
		"mediaDetected":  {Title: "震动报警", Body: "{{device}} 检测到震动"},
		"motionDetected": {Title: "移动", Body: "{{device}} 检测到移动"},
		"maintenance":    {Title: "保养到期", Body: "{{device}} 保养里程到期"},
		"commandResult":  {Title: "指令结果", Body: "{{device}} 指令执行结果：{{value}}"},
		"deviceOnline":   {Title: "设备上线", Body: "{{device}} 已上线"},
		"deviceOffline":  {Title: "设备离线", Body: "{{device}} 已离线"},
	}
	renderer.templates["en"] = map[string]Template{
		"geofenceEnter":  {Title: "Geofence entered", Body: "{{device}} entered geofence {{geofence}}"},
		"geofenceExit":   {Title: "Geofence exited", Body: "{{device}} left geofence {{geofence}}"},
		"alarm":          {Title: "Alarm", Body: "{{device}} triggered an alarm"},
		"ignitionOn":     {Title: "Ignition on", Body: "{{device}} ignition is on"},
		"ignitionOff":    {Title: "Ignition off", Body: "{{device}} ignition is off"},
		"speeding":       {Title: "Speeding", Body: "{{device}} is speeding at {{speed}} km/h"},
		"mediaDetected":  {Title: "Impact detected", Body: "{{device}} detected an impact"},
		"motionDetected": {Title: "Motion detected", Body: "{{device}} detected motion"},
		"maintenance":    {Title: "Maintenance due", Body: "{{device}} maintenance is due"},
		"commandResult":  {Title: "Command result", Body: "{{device}} command result: {{value}}"},
		"deviceOnline":   {Title: "Device online", Body: "{{device}} is online"},
		"deviceOffline":  {Title: "Device offline", Body: "{{device}} is offline"},
	}
	renderer.fallback = map[string]Template{
		"zh": {Title: "设备事件", Body: "{{device}} 发生事件 {{eventType}}"},
		"en": {Title: "Device event", Body: "{{device}} reported event {{eventType}}"},
	}
	return renderer
}

// Render 渲染指定语言的通知文案。
func (r *Renderer) Render(event model.TraccarEvent, locale string) (title, body string) {
	locale = normalizeLocale(locale)
	templates, ok := r.templates[locale]
	if !ok {
		locale = "zh"
		templates = r.templates["zh"]
	}
	entry, ok := templates[event.Event.Type]
	if !ok {
		entry = r.fallback[locale]
	}
	values := buildValues(event)
	return fill(entry.Title, values), fill(entry.Body, values)
}

func normalizeLocale(locale string) string {
	locale = strings.ToLower(strings.TrimSpace(locale))
	switch {
	case locale == "" || strings.HasPrefix(locale, "zh"):
		if strings.Contains(locale, "hant") || strings.Contains(locale, "tw") {
			return "zh"
		}
		return "zh"
	case strings.HasPrefix(locale, "en"):
		return "en"
	default:
		return "zh"
	}
}

func buildValues(event model.TraccarEvent) map[string]string {
	values := map[string]string{
		"device":    firstNonEmpty(event.DeviceName, fmt.Sprintf("设备 %d", event.DeviceID)),
		"deviceId":  strconv.FormatInt(event.DeviceID, 10),
		"eventType": event.Event.Type,
		"eventId":   strconv.FormatInt(event.Event.ID, 10),
		"userId":    strconv.FormatInt(event.UserID, 10),
	}
	attributes := event.Event.Attributes
	if attributes == nil && event.Position != nil {
		attributes = event.Position.Attributes
	}
	if value, ok := attributes["geofenceName"]; ok {
		values["geofence"] = toString(value)
	} else if event.Event.GeofenceID > 0 {
		values["geofence"] = strconv.FormatInt(event.Event.GeofenceID, 10)
	} else {
		values["geofence"] = "-"
	}
	values["speed"] = attributeString(attributes, "speed", "-")
	values["battery"] = attributeString(attributes, "batteryLevel", "-")
	values["value"] = attributeString(attributes, "value", "-")
	values["alarmType"] = attributeString(attributes, "alarmType", "-")
	return values
}

func attributeString(attributes map[string]any, key, fallback string) string {
	if attributes == nil {
		return fallback
	}
	if value, ok := attributes[key]; ok {
		return toString(value)
	}
	return fallback
}

func toString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(typed)
	case nil:
		return ""
	default:
		return fmt.Sprintf("%v", typed)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func fill(text string, values map[string]string) string {
	for key, value := range values {
		text = strings.ReplaceAll(text, "{{"+key+"}}", value)
	}
	return text
}

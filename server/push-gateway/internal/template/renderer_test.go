package template

import (
	"testing"

	"github.com/trackerone/push-gateway/internal/model"
)

func TestRenderChinese(t *testing.T) {
	renderer := New()
	event := model.TraccarEvent{
		DeviceID:   7,
		DeviceName: "京A·12345",
		UserID:     42,
		Event: model.Event{
			ID:         555,
			Type:       "geofenceEnter",
			GeofenceID: 9,
			Attributes: map[string]any{"geofenceName": "公司"},
		},
	}

	title, body := renderer.Render(event, "zh")
	if title != "围栏进入" {
		t.Fatalf("标题错误: %s", title)
	}
	if body != "京A·12345 进入围栏「公司」" {
		t.Fatalf("正文错误: %s", body)
	}
}

func TestRenderEnglishFallback(t *testing.T) {
	renderer := New()
	event := model.TraccarEvent{
		DeviceID: 7,
		Event:    model.Event{ID: 1, Type: "unknownType"},
	}

	title, body := renderer.Render(event, "en")
	if title != "Device event" {
		t.Fatalf("英文回退标题错误: %s", title)
	}
	if body == "" {
		t.Fatal("英文回退正文为空")
	}
}

func TestRenderUsesPositionAttributes(t *testing.T) {
	renderer := New()
	event := model.TraccarEvent{
		DeviceID: 7,
		Event:    model.Event{ID: 1, Type: "speeding"},
		Position: &model.Position{
			Attributes: map[string]any{"speed": 88.5},
		},
	}

	_, body := renderer.Render(event, "zh")
	if body != "设备 7 超速，速度 88.5 km/h" {
		t.Fatalf("速度属性未渲染: %s", body)
	}
}

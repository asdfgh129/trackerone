package store

import (
	"context"
	"testing"
	"time"

	"github.com/trackerone/push-gateway/internal/model"
)

func TestMemoryInboxPaginationAndAck(t *testing.T) {
	ctx := context.Background()
	storage := NewMemory(time.Hour, time.Hour)
	now := time.Unix(1_700_000_000, 0)
	storage.SetClock(func() time.Time { return now })

	first, err := storage.PutInboxMessage(ctx, model.InboxMessage{
		UserID:   42,
		ServerID: 1,
		Kind:     "notice",
		Title:    "first",
	})
	if err != nil {
		t.Fatalf("put first: %v", err)
	}
	second, err := storage.PutInboxMessage(ctx, model.InboxMessage{
		UserID:   42,
		ServerID: 1,
		Kind:     "chat",
		Title:    "second",
	})
	if err != nil {
		t.Fatalf("put second: %v", err)
	}
	if first.ID == "" || first.Seq >= second.Seq {
		t.Fatalf("unexpected ids/seq: %#v %#v", first, second)
	}
	if _, err := storage.PutInboxMessage(ctx, model.InboxMessage{
		UserID:   7,
		ServerID: 1,
		Kind:     "notice",
	}); err != nil {
		t.Fatalf("put other user: %v", err)
	}

	messages, err := storage.ListInboxMessages(ctx, 42, 1, 0, 10)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(messages) != 2 || messages[0].ID != first.ID || messages[1].ID != second.ID {
		t.Fatalf("unexpected messages: %#v", messages)
	}

	after, err := storage.ListInboxMessages(ctx, 42, 1, first.Seq, 10)
	if err != nil {
		t.Fatalf("list after: %v", err)
	}
	if len(after) != 1 || after[0].ID != second.ID {
		t.Fatalf("unexpected incremental messages: %#v", after)
	}

	if ok, err := storage.AckInboxMessage(ctx, 42, 1, first.ID, now); err != nil || !ok {
		t.Fatalf("ack first: ok=%v err=%v", ok, err)
	}
	if ok, _ := storage.AckInboxMessage(ctx, 7, 1, first.ID, now); ok {
		t.Fatal("ack from another user must fail")
	}
	if ok, _ := storage.AckInboxMessage(ctx, 42, 2, first.ID, now); ok {
		t.Fatal("ack from another server must fail")
	}

	if err := storage.DeleteInboxMessages(ctx, 42, 1); err != nil {
		t.Fatalf("delete: %v", err)
	}
	remaining, err := storage.ListInboxMessages(ctx, 42, 1, 0, 10)
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(remaining) != 0 {
		t.Fatalf("expected empty inbox, got %#v", remaining)
	}
	if other, _ := storage.ListInboxMessages(ctx, 7, 1, 0, 10); len(other) != 1 {
		t.Fatalf("delete must not touch other users: %#v", other)
	}
}

func TestMemoryInboxExpiryAndLimit(t *testing.T) {
	ctx := context.Background()
	storage := NewMemory(time.Hour, time.Hour)
	now := time.Unix(1_700_000_000, 0)
	storage.SetClock(func() time.Time { return now })

	expired := now.Add(-time.Minute)
	if _, err := storage.PutInboxMessage(ctx, model.InboxMessage{
		UserID:    42,
		ServerID:  1,
		Kind:      "notice",
		ExpiresAt: &expired,
	}); err != nil {
		t.Fatalf("put expired: %v", err)
	}
	for i := 0; i < 3; i++ {
		if _, err := storage.PutInboxMessage(ctx, model.InboxMessage{
			UserID:   42,
			ServerID: 1,
			Kind:     "notice",
		}); err != nil {
			t.Fatalf("put live: %v", err)
		}
	}

	latest, err := storage.ListInboxMessages(ctx, 42, 1, 0, 2)
	if err != nil {
		t.Fatalf("list latest: %v", err)
	}
	if len(latest) != 2 {
		t.Fatalf("expected newest two messages, got %#v", latest)
	}
	all, err := storage.ListInboxMessages(ctx, 42, 1, 0, 10)
	if err != nil {
		t.Fatalf("list all: %v", err)
	}
	if len(all) != 3 {
		t.Fatalf("expired message must be hidden, got %#v", all)
	}
	if all[0].Seq >= all[1].Seq || all[1].Seq >= all[2].Seq {
		t.Fatalf("messages must be ascending by seq: %#v", all)
	}
}

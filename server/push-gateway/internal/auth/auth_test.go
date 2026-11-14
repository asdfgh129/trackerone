package auth

import "testing"

func TestSignAndVerify(t *testing.T) {
	secret := "test-secret"
	body := []byte(`{"event":{"id":1}}`)

	signature := Sign(secret, body)
	if err := Verify(secret, body, signature); err != nil {
		t.Fatalf("合法签名校验失败: %v", err)
	}
	// 允许裸 hex。
	if err := Verify(secret, body, signature[len("sha256="):]); err != nil {
		t.Fatalf("裸 hex 签名校验失败: %v", err)
	}
	if err := Verify(secret, body, "sha256=deadbeef"); err == nil {
		t.Fatal("错误签名应当被拒绝")
	}
	if err := Verify(secret, []byte("other"), signature); err == nil {
		t.Fatal("请求体被篡改时应当被拒绝")
	}
	if err := Verify(secret, body, ""); err == nil {
		t.Fatal("缺少签名头应当被拒绝")
	}
}

func TestAliasRoundTrip(t *testing.T) {
	if got := AliasFor(42, 1); got != "u42@1" {
		t.Fatalf("别名格式错误: %s", got)
	}
	userID, serverID, err := ParseAlias("u42@1")
	if err != nil {
		t.Fatalf("解析别名失败: %v", err)
	}
	if userID != 42 || serverID != 1 {
		t.Fatalf("解析结果错误: %d %d", userID, serverID)
	}
	for _, invalid := range []string{"", "u42", "@1", "u42@", "u0@1", "ux@1", "u42@x"} {
		if _, _, err := ParseAlias(invalid); err == nil {
			t.Fatalf("非法别名 %q 应当被拒绝", invalid)
		}
	}
}

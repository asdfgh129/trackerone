// Package httpapi 暴露网关的 HTTP 接口。
package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/trackerone/push-gateway/internal/gateway"
	"github.com/trackerone/push-gateway/internal/model"
	"github.com/trackerone/push-gateway/internal/store"
)

// Server 是 HTTP 处理器集合。
type Server struct {
	service *gateway.Service
	store   store.Store
	log     *slog.Logger
	admin   string
}

// NewServer 创建 HTTP 处理器。
func NewServer(service *gateway.Service, storage store.Store, adminToken string, logger *slog.Logger) *Server {
	return &Server{
		service: service,
		store:   storage,
		log:     logger,
		admin:   adminToken,
	}
}

// Register 注册全部路由。
func (s *Server) Register(mux *http.ServeMux) {
	mux.HandleFunc("/v1/events", s.handleEvent)
	mux.HandleFunc("/v1/aliases", s.handleAliasCollection)
	mux.HandleFunc("/v1/aliases/", s.handleAliasItem)
	mux.HandleFunc("/v1/messages", s.handleMessages)
	mux.HandleFunc("/v1/messages/audit", s.handleMessagesAudit)
	mux.HandleFunc("/v1/messages/", s.handleMessageItem)
	mux.HandleFunc("/v1/dead", s.handleDeadLetters)
	mux.HandleFunc("/v1/flush", s.handleFlush)
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/readyz", s.handleReady)
	s.registerAdmin(mux)
}

// handleEvent 接收 Traccar webhook。
func (s *Server) handleEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 POST"})
		return
	}
	body := http.MaxBytesReader(w, r.Body, 1<<20)
	raw, err := io.ReadAll(body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "读取请求体失败"})
		return
	}

	locale := r.Header.Get("X-Locale")
	result, err := s.service.HandleEvent(r.Context(), raw, r.Header.Get("X-Traccar-Signature"), locale)
	if errors.Is(err, gateway.ErrUnauthorized) {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "签名校验失败"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, result)
}

// handleAliasCollection 处理别名注册（POST）与列表（GET，管理员）。
func (s *Server) handleAliasCollection(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		token := bearerToken(r)
		var request model.AliasRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&request); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "解析请求体失败"})
			return
		}
		alias, err := s.service.RegisterAlias(r.Context(), token, request)
		if errors.Is(err, gateway.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": err.Error()})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, alias)
	case http.MethodGet:
		if !s.requireAdmin(w, r) {
			return
		}
		aliases, err := s.store.ListAliases(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"aliases": aliases})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 GET / POST"})
	}
}

// handleAliasItem 处理别名删除。
func (s *Server) handleAliasItem(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 DELETE"})
		return
	}
	alias := strings.TrimPrefix(r.URL.Path, "/v1/aliases/")
	if alias == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "缺少别名"})
		return
	}
	if err := s.service.UnregisterAlias(r.Context(), bearerToken(r), alias); err != nil {
		if errors.Is(err, gateway.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "deleted", "alias": alias})
}

// handleDeadLetters 返回死信列表（管理员）。
func (s *Server) handleDeadLetters(w http.ResponseWriter, r *http.Request) {
	if !s.requireAdmin(w, r) {
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListDeadLetters(r.Context(), limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deadLetters": items})
}

// handleFlush 手动触发延后队列投递（管理员）。
func (s *Server) handleFlush(w http.ResponseWriter, r *http.Request) {
	if !s.requireAdmin(w, r) {
		return
	}
	sent, err := s.service.FlushDeferred(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sent": sent})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Ping(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"status": "unavailable", "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ready"})
}

func (s *Server) requireAdmin(w http.ResponseWriter, r *http.Request) bool {
	if s.admin == "" {
		writeJSON(w, http.StatusForbidden, map[string]any{"error": "未配置 ADMIN_TOKEN，禁用管理接口"})
		return false
	}
	token := bearerToken(r)
	if token == "" || token != s.admin {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "需要管理员令牌"})
		return false
	}
	return true
}

func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if header == "" {
		return ""
	}
	if strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return strings.TrimSpace(header[7:])
	}
	return strings.TrimSpace(header)
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		return
	}
}

// handleMessages 处理收件箱：拉取（用户）、下发（管理员）、清空（管理员）。
func (s *Server) handleMessages(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		messages, cursor, err := s.service.ListMessages(
			r.Context(),
			bearerToken(r),
			r.URL.Query().Get("since"),
			limit,
		)
		if errors.Is(err, gateway.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "Token 无效"})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"messages":   messages,
			"nextCursor": cursor,
		})
	case http.MethodPost:
		// 管理端用 ADMIN_TOKEN；Traccar 用现有 webhook HMAC 直接写入收件箱，
		// 避免把管理令牌配置到 Traccar 服务器上。
		raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "读取请求体失败"})
			return
		}
		source := ""
		if s.admin != "" && bearerToken(r) == s.admin {
			source = gateway.SourceAdmin
		} else if err := s.service.VerifyTraccarSignature(raw, r.Header.Get("X-Traccar-Signature")); err == nil {
			source = gateway.SourceTraccar
		} else {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "需要管理员令牌或有效的 Traccar 签名"})
			return
		}
		var request model.InboxSendRequest
		if err := json.Unmarshal(raw, &request); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "解析请求体失败"})
			return
		}
		request.Source = source
		message, push, err := s.service.SendMessage(r.Context(), request)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{
			"message": message,
			"push":    push,
		})
	case http.MethodDelete:
		if !s.requireAdmin(w, r) {
			return
		}
		userID, _ := strconv.ParseInt(r.URL.Query().Get("userId"), 10, 64)
		serverID, _ := strconv.ParseInt(r.URL.Query().Get("serverId"), 10, 64)
		if err := s.service.DeleteMessages(r.Context(), userID, serverID); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"status": "deleted"})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 GET / POST / DELETE"})
	}
}

// handleMessagesAudit 返回管理端审计消息（分页，按时间倒序）。
func (s *Server) handleMessagesAudit(w http.ResponseWriter, r *http.Request) {
	if !s.requireAdmin(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 GET"})
		return
	}
	userID, _ := strconv.ParseInt(r.URL.Query().Get("userId"), 10, 64)
	serverID, _ := strconv.ParseInt(r.URL.Query().Get("serverId"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	messages, next, err := s.service.ListAudit(
		r.Context(),
		userID,
		serverID,
		r.URL.Query().Get("cursor"),
		limit,
	)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"messages":   messages,
		"nextCursor": next,
	})
}

// handleMessageItem 处理消息级操作：
//
//	POST /v1/messages/{id}/ack     用户投递回执
//	POST /v1/messages/{id}/revoke  管理员撤回
//	POST /v1/messages/{id}/resend  管理员重发壳通知
func (s *Server) handleMessageItem(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 POST"})
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/v1/messages/")
	switch {
	case strings.HasSuffix(rest, "/ack"):
		id := strings.TrimSuffix(rest, "/ack")
		if id == "" {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "缺少消息 id"})
			return
		}
		err := s.service.AckMessage(r.Context(), bearerToken(r), id)
		switch {
		case errors.Is(err, gateway.ErrUnauthorized):
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "Token 无效"})
		case errors.Is(err, gateway.ErrNotFound):
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "消息不存在"})
		case err != nil:
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
		default:
			w.WriteHeader(http.StatusNoContent)
		}
	case strings.HasSuffix(rest, "/revoke"):
		if !s.requireAdmin(w, r) {
			return
		}
		id := strings.TrimSuffix(rest, "/revoke")
		userID, _ := strconv.ParseInt(r.URL.Query().Get("userId"), 10, 64)
		serverID, _ := strconv.ParseInt(r.URL.Query().Get("serverId"), 10, 64)
		message, err := s.service.RevokeMessage(r.Context(), userID, serverID, id)
		if errors.Is(err, gateway.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "消息不存在"})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"message": message})
	case strings.HasSuffix(rest, "/resend"):
		if !s.requireAdmin(w, r) {
			return
		}
		id := strings.TrimSuffix(rest, "/resend")
		userID, _ := strconv.ParseInt(r.URL.Query().Get("userId"), 10, 64)
		serverID, _ := strconv.ParseInt(r.URL.Query().Get("serverId"), 10, 64)
		message, push, err := s.service.ResendMessage(r.Context(), userID, serverID, id)
		if errors.Is(err, gateway.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "消息不存在"})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"message": message, "push": push})
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "未知接口"})
	}
}

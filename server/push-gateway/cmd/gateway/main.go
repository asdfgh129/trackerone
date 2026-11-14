// 推送网关入口。
//
// 用法：
//
//	TRACCAR_WEBHOOK_SECRET=xxx JPUSH_APP_KEY=xxx JPUSH_MASTER_SECRET=xxx \
//	REDIS_ADDR=127.0.0.1:6379 ./gateway
//
// 本地联调可以加 DRY_RUN=true（不调用极光）与 STORE_BACKEND=memory（不用 Redis）。
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/trackerone/push-gateway/internal/auth"
	"github.com/trackerone/push-gateway/internal/config"
	"github.com/trackerone/push-gateway/internal/gateway"
	"github.com/trackerone/push-gateway/internal/httpapi"
	"github.com/trackerone/push-gateway/internal/jpush"
	"github.com/trackerone/push-gateway/internal/store"
	"github.com/trackerone/push-gateway/internal/template"
)

func main() {
	if err := run(); err != nil {
		slog.Error("网关启动失败", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	logger := newLogger(cfg.LogLevel)
	slog.SetDefault(logger)

	var storage store.Store
	if cfg.StoreBackend == "memory" {
		storage = store.NewMemory(cfg.AliasTTL, cfg.IdempotencyTTL)
		logger.Warn("使用内存存储，重启后数据丢失，仅适用于本地联调")
	} else {
		storage = store.NewRedis(cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB, cfg.AliasTTL)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := storage.Ping(ctx); err != nil {
			cancel()
			return err
		}
		cancel()
	}
	defer storage.Close()

	client := jpush.New(jpush.Options{
		AppKey:         cfg.JPushAppKey,
		MasterSecret:   cfg.JPushMasterSecret,
		BaseURL:        cfg.JPushAPIBase,
		Channel:        cfg.JPushChannel,
		TTL:            cfg.JPushTTL,
		APNSProduction: cfg.JPushAPNSProduction,
		DryRun:         cfg.DryRun,
	})

	traccar := auth.NewTraccarClient(cfg.TraccarBaseURL, cfg.TraccarTimeout)
	service := gateway.New(cfg, storage, client, template.New(), traccar, logger)
	server := httpapi.NewServer(service, storage, cfg.AdminToken, logger)

	mux := http.NewServeMux()
	server.Register(mux)

	httpServer := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           logging(logger, mux),
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// 延后队列（限流合并 / 免打扰）定时投递。
	workerCtx, stopWorker := context.WithCancel(context.Background())
	defer stopWorker()
	go runWorker(workerCtx, service, cfg.FlushInterval, logger)

	go func() {
		logger.Info(
			"推送网关已启动",
			"addr", cfg.ListenAddr,
			"store", cfg.StoreBackend,
			"dryRun", cfg.DryRun,
			"traccar", cfg.TraccarBaseURL,
			"quietHours", cfg.QuietHours,
		)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("HTTP 服务退出", "error", err)
			stopWorker()
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Info("收到退出信号，开始优雅关闭")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		return err
	}
	stopWorker()
	return nil
}

// runWorker 周期性投递延后队列。
func runWorker(ctx context.Context, service *gateway.Service, interval time.Duration, logger *slog.Logger) {
	if interval <= 0 {
		interval = time.Minute
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sent, err := service.FlushDeferred(ctx)
			if err != nil {
				logger.Error("延后队列投递失败", "error", err)
				continue
			}
			if sent > 0 {
				logger.Info("延后队列已投递", "count", sent)
			}
		}
	}
}

// logging 给每个请求加访问日志。
func logging(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		logger.Info(
			"http",
			"method", r.Method,
			"path", r.URL.Path,
			"status", recorder.status,
			"duration", time.Since(start).String(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func newLogger(level string) *slog.Logger {
	var slogLevel slog.Level
	switch level {
	case "debug":
		slogLevel = slog.LevelDebug
	case "warn":
		slogLevel = slog.LevelWarn
	case "error":
		slogLevel = slog.LevelError
	default:
		slogLevel = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slogLevel}))
}

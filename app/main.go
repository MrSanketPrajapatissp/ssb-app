// ssb-app: Minimal HTTP service for SSB Digital DevOps take-home assignment.
// Exposes /health, /ready, and /metrics endpoints.
// Built with zero external dependencies beyond the Prometheus client library.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Build-time variables injected via -ldflags.
var (
	version   = "dev"
	gitCommit = "unknown"
	buildTime = "unknown"
)

// HealthResponse is the JSON body for /health and /ready.
type HealthResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version"`
	Commit    string `json:"commit"`
	Timestamp string `json:"timestamp"`
}

func main() {
	// Structured JSON logging — required for production log aggregation.
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// --- Prometheus metrics setup ---
	reg := prometheus.NewRegistry()

	// Standard Go runtime metrics.
	reg.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)

	// Custom application metrics.
	httpRequestsTotal := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: "ssb",
			Subsystem: "app",
			Name:      "http_requests_total",
			Help:      "Total number of HTTP requests partitioned by method, path, and status code.",
		},
		[]string{"method", "path", "status_code"},
	)
	reg.MustRegister(httpRequestsTotal)

	httpRequestDuration := prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: "ssb",
			Subsystem: "app",
			Name:      "http_request_duration_seconds",
			Help:      "HTTP request duration in seconds partitioned by method and path.",
			Buckets:   prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)
	reg.MustRegister(httpRequestDuration)

	buildInfo := prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "ssb",
			Subsystem: "app",
			Name:      "build_info",
			Help:      "Build information about the running ssb-app instance.",
		},
		[]string{"version", "commit", "build_time"},
	)
	reg.MustRegister(buildInfo)
	buildInfo.WithLabelValues(version, gitCommit, buildTime).Set(1)

	// --- HTTP handler setup ---
	mux := http.NewServeMux()

	// /health — liveness probe: always returns 200 if the process is alive.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		resp := HealthResponse{
			Status:    "ok",
			Version:   version,
			Commit:    gitCommit,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			slog.Error("failed to encode health response", "error", err)
		}
		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, "/health", "200").Inc()
		httpRequestDuration.WithLabelValues(r.Method, "/health").Observe(duration)
	})

	// /ready — readiness probe: returns 200 when the service is ready to accept traffic.
	// In production, this would check DB connections, caches, etc.
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		resp := HealthResponse{
			Status:    "ready",
			Version:   version,
			Commit:    gitCommit,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			slog.Error("failed to encode ready response", "error", err)
		}
		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, "/ready", "200").Inc()
		httpRequestDuration.WithLabelValues(r.Method, "/ready").Observe(duration)
	})

	// /metrics — Prometheus exposition format.
	mux.Handle("/metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{
		EnableOpenMetrics: true,
	}))

	// / — default route for basic service info.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, "404").Inc()
			return
		}
		start := time.Now()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"service":"ssb-app","version":%q,"commit":%q}`, version, gitCommit)
		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, "/", "200").Inc()
		httpRequestDuration.WithLabelValues(r.Method, "/").Observe(duration)
	})

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	// Graceful shutdown on SIGTERM / SIGINT.
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
		sig := <-sigCh
		slog.Info("received signal, shutting down", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			slog.Error("graceful shutdown failed", "error", err)
			os.Exit(1)
		}
	}()

	slog.Info("ssb-app starting",
		"port", port,
		"version", version,
		"commit", gitCommit,
		"build_time", buildTime,
	)

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}

	slog.Info("ssb-app shutdown complete")
}

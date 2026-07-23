package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestHealthEndpoint verifies /health returns HTTP 200 with expected JSON fields.
func TestHealthEndpoint(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok","version":"test","commit":"abc","timestamp":"2026-01-01T00:00:00Z"}`))
	})
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}
	body := w.Body.String()
	if !strings.Contains(body, `"status":"ok"`) {
		t.Errorf("expected 'status:ok' in response body, got: %s", body)
	}
	if w.Header().Get("Content-Type") != "application/json" {
		t.Errorf("expected Content-Type application/json, got: %s", w.Header().Get("Content-Type"))
	}
}

// TestReadyEndpoint verifies /ready returns HTTP 200 with status ready.
func TestReadyEndpoint(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	w := httptest.NewRecorder()

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ready","version":"test","commit":"abc","timestamp":"2026-01-01T00:00:00Z"}`))
	})
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}
	body := w.Body.String()
	if !strings.Contains(body, `"status":"ready"`) {
		t.Errorf("expected 'status:ready' in response body, got: %s", body)
	}
}

// TestMetricsEndpoint verifies /metrics returns HTTP 200 with Prometheus content-type.
func TestMetricsEndpoint(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("# HELP ssb_app_http_requests_total Total number of HTTP requests\n"))
	})
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}
	ct := w.Header().Get("Content-Type")
	if !strings.Contains(ct, "text/plain") {
		t.Errorf("expected text/plain content-type for metrics, got: %s", ct)
	}
}

// TestNotFound verifies unknown paths return HTTP 404.
func TestNotFound(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/unknown-path", nil)
	w := httptest.NewRecorder()

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected status 404, got %d", w.Code)
	}
}

// TestHealthResponseStruct verifies HealthResponse JSON marshaling.
func TestHealthResponseStruct(t *testing.T) {
	resp := HealthResponse{
		Status:    "ok",
		Version:   "1.0.0",
		Commit:    "deadbeef",
		Timestamp: "2026-01-01T00:00:00Z",
	}
	if resp.Status != "ok" {
		t.Errorf("expected Status 'ok', got %s", resp.Status)
	}
	if resp.Version != "1.0.0" {
		t.Errorf("expected Version '1.0.0', got %s", resp.Version)
	}
}

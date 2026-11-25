package httpapi

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed admin/index.html admin/app.js admin/app.css
var adminAssets embed.FS

// registerAdmin 注册内置运营台。
//
// 页面本身不含业务数据，所有操作都由浏览器携带管理员令牌调用管理接口，
// 因此可以公开托管；生产环境建议在反向代理层再加一层访问控制（IP 白名单 / SSO）。
func (s *Server) registerAdmin(mux *http.ServeMux) {
	sub, err := fs.Sub(adminAssets, "admin")
	if err != nil {
		// embed 路径在编译期固定，正常不会失败。
		panic("admin assets: " + err.Error())
	}
	files := http.StripPrefix("/admin/", http.FileServer(http.FS(sub)))

	mux.HandleFunc("/admin", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/admin/", http.StatusMovedPermanently)
	})
	mux.HandleFunc("/admin/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "仅支持 GET / HEAD"})
			return
		}
		setAdminHeaders(w)
		files.ServeHTTP(w, r)
	})
}

// setAdminHeaders 为运营台设置严格的安全响应头。
//
// 页面不引用任何外部资源，因此 CSP 可以收紧到同源脚本 / 样式，
// 同时禁止被 iframe 嵌入与被搜索引擎收录。
func setAdminHeaders(w http.ResponseWriter) {
	header := w.Header()
	header.Set("Content-Security-Policy",
		"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "+
			"connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
	header.Set("X-Frame-Options", "DENY")
	header.Set("X-Content-Type-Options", "nosniff")
	header.Set("Referrer-Policy", "no-referrer")
	header.Set("X-Robots-Tag", "noindex, nofollow")
	header.Set("Cache-Control", "no-store")
}

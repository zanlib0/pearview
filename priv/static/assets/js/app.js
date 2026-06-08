// Application JavaScript. Intentionally minimal — the app is server-rendered
// HEEx with no JS build step (see docs/adr/0001-htmx-masthead-over-liveview.md).

// Carry Phoenix's CSRF token on every HTMX request so non-GET fragment swaps
// (edit/delete) pass `protect_from_forgery` without a per-control hidden input.
document.addEventListener("htmx:configRequest", (event) => {
  const token = document.querySelector("meta[name='csrf-token']");
  if (token) {
    event.detail.headers["x-csrf-token"] = token.content;
  }
});

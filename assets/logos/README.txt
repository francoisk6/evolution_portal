Per-workspace header logos.

Drop a wide wordmark PNG named <workspace-slug>.png here (e.g. dmp.png) and the
header picks it up automatically - no code change. Roughly 4:1, sized for a
28px-tall app bar, so ~600x150 with a transparent background.

The Main/Evolution workspace uses assets/logo.png instead, kept where it is so
nothing about the existing brand moves.

A workspace with no file here falls back to the styled text wordmark
(BrandWordmark) showing its name - deliberately NOT Evolution's logo, which
would put the wrong brand in a tenant's app.

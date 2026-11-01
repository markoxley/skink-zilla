# skink-zilla

Fiber-style web framework for Skink, built on `std/web`. A thin,
ergonomic layer (`Ctx`, `App`, groups, `UseWeb` middleware) plus a
complete feature set: JWT, sessions, authz, rate limiting, CORS,
multipart uploads, and WebSocket.

```
scales add markoxley/skink-zilla
```

## Quick start

```skink
import "mod/markoxley/skink-zilla"
import "mod/markoxley/skink-zilla/zilla_ctx"
import "mod/markoxley/skink-zilla/zilla_app"

fn main() {
    app := zilla.New(8080)

    zilla_app.Get(&app, "/hello", fn(c: *zilla_ctx.Ctx) {
        zilla_ctx.Text(c, 200, "hi")
    })
    zilla_app.Get(&app, "/user/:id", fn(c: *zilla_ctx.Ctx) {
        zilla_ctx.Text(c, 200, zilla_ctx.Param(c, "id"))
    })

    zilla_app.Listen(&app)
}
```

## Middleware

```skink
import "mod/markoxley/skink-zilla/zilla_authz"

// app-wide, applied at request time — order is registration order
zilla_app.UseWeb(&app, fn(next: fn(*zilla_ctx.Ctx)) -> fn(*zilla_ctx.Ctx) {
    return fn(c: *zilla_ctx.Ctx) {
        zilla_ctx.SetLocal(c, "seen", "1")
        next(c)
    }
})

// group-scoped (registered before the group's routes)
api := zilla_app.GroupAt(&app, "/api")
zilla_app.GroupUse(&api, zilla_authz.RequireAuth("my-secret"))
zilla_app.GroupGet(&api, "/who", handler)
```

## Features

**JWT** (`zilla_jwt`) — HS256 sign/verify, `exp`/`nbf` enforcement,
alg-confusion rejected:

```skink
import "mod/markoxley/skink-zilla/zilla_jwt"

tok := zilla_jwt.Sign("{\"sub\":\"u1\"}", secret, int64(3600))
cl, err := zilla_jwt.Verify(tok, secret)   // cl.Raw / zilla_jwt.Get(&cl,"sub")
```

**Authz** (`zilla_authz`) — `RequireAuth(secret)` verifies
`Authorization: Bearer`, stores claims JSON in
`Locals["zilla.jwt_claims"]` + `Locals["zilla.sub"]`. `RequireRole(r)`
accepts JSON-array or comma-separated `roles` claims;
`RequireClaim(k,v)` matches any claim. 401 unauthenticated, 403
unauthorized.

**Sessions** (`zilla_session`) — mutex-guarded in-memory store with
sliding TTL + cookie `skink_sid`:

```skink
import "mod/markoxley/skink-zilla/zilla_session"

store := zilla_session.NewStore(int64(3600), "")
sess := zilla_session.Get(&store, c)
zilla_session.SSet(&sess, "user", "ada")
zilla_session.Regenerate(&sess, c)   // anti-fixation
zilla_session.Destroy(&sess, c)
```

**Rate limiting** (`zilla_ratelimit`) — fixed window per key
(default client IP, or a named header like `x-api-key`), 429 +
`Retry-After`. `zilla_ctx.IP` returns the real socket peer when the
request came from `std/web`'s server (unforgeable — never from
headers); `remote_addr` and `x-forwarded-for` are only fallbacks, so
behind a trusted proxy supply a named key or override the header:

```skink
import "mod/markoxley/skink-zilla/zilla_ratelimit"

lim := zilla_ratelimit.NewLimiter(100, int64(60))
zilla_app.UseWeb(&app, zilla_ratelimit.Middleware(&lim, ""))
```

**CORS** (`zilla_cors`) — headers on matched routes *and* an
`OPTIONS /*` preflight catch-all (std/web 404s unmatched routes before
middleware, so use `Install` which does both):

```skink
import "mod/markoxley/skink-zilla/zilla_cors"

zilla_cors.Install(&app, zilla_cors.DefaultConfig())
```

**Uploads** (`zilla_upload`) — multipart/form-data parsing,
binary-safe (`Part.DataLen` is authoritative, `Data` may hold NULs):

```skink
import "mod/markoxley/skink-zilla/zilla_upload"

title := zilla_upload.FormValue(c, "title")
part, ok := zilla_upload.FormFile(c, "doc")   // part.Filename/.Data
```

**WebSocket** (`zilla_ws`) — RFC 6455 over `ResponseWriter.Hijack`
(works on plain TCP and TLS connections; the buffered-byte handoff is
handled):

```skink
import "mod/markoxley/skink-zilla/zilla_ws"
import "std/str"

fn hWS(c: *zilla_ctx.Ctx) {
    zilla_ws.Upgrade(c, fn(ws: *zilla_ws.Conn) {
        for {
            f, err := zilla_ws.Read(ws)
            if str.Len(err.message) > 0 { break }
            if f.Op == zilla_ws.OP_CLOSE { break }
            if f.Op == zilla_ws.OP_PING  { zilla_ws.Pong(ws, f.Data, f.Len); continue }
            zilla_ws.Write(ws, f.Op, f.Data, f.Len)   // echo
        }
        zilla_ws.Close(ws)
    })
}
zilla_app.Get(&app, "/ws", hWS)
```

Client frames must be masked (per spec); server frames are sent
unmasked. `Read` returns `Frame{Op, Data, Len, Fin}`; helpers
`WriteText`, `WriteBinary`, `Ping`, `Pong`, `Close`.

**Static files**:

```skink
zilla_app.Static(&app, "/static", "./public")
```

**Ctx API** — `Param`, `Query`, `QueryDefault`, `Body`, `BodyBytes`,
`Header`, `IP` (X-Forwarded-For aware), `ParseJSON`, `Set`, `Status`,
`Send`/`Text`/`JSON`/`JSONValue`/`HTML`/`SendStatus`, `Redirect`,
`Cookie`/`SetCookie`/`ClearCookie`, `SetLocal`/`Local`.

## Testing

- `bash run_tests.sh` — unit suites (`jwt_test`, `mw_test`) + a live
  server test (`live_test` spawns a real App on port 18211 and drives
  routes/JWT/ratelimit/CORS/upload/WebSocket over raw TCP).
- `bash install_local.sh` — publish to the local
  `SCALES_GITHUB_MIRROR` and verify a consumer can `scales add` + build.

## Notes & limits

- `Pub type` aliases don't unify across modules — middleware
  signatures use the canonical `fn(fn(*zilla_ctx.Ctx)) -> fn(*zilla_ctx.Ctx)`.
- Session store is in-memory (no Redis backend yet).
- JWT is HS256 only — asymmetric algs are a future addition.
- Nested `map[string]map[string]string` hits an emitter gap — the
  session store boxes the inner map behind `*SessData`.

# Codex Pet Bar website

A static SvelteKit site, hosted directly on Cloudflare Workers at https://pet.ajt.dev/. The homepage and `/landing/` use the same design. Earlier directions remain under `design/archive/` and are not deployed.

```sh
bun install --frozen-lockfile
bun run dev
```

Validate the site at the domain root (no `BASE_PATH`):

```sh
bun run check
bun run build
bun run test
```

Deploy using the Cloudflare account that owns `ajt.dev` (Andrewjtyler1@gmail.com, account ID `da6ee7275bc045f55d74ef45b2c13469`):

```sh
bunx wrangler login
bun run deploy
```

`wrangler.jsonc` declares the static build directory and `pet.ajt.dev` custom domain. Cloudflare manages the hostname and TLS certificate. GitHub Actions runs the website checks; it no longer deploys to GitHub Pages. Deployment is explicit using the command above.

The native application continues to be distributed through GitHub Releases and Homebrew. The downloadable release is v0.1.2; the interactive site demo is labelled as a v0.2 preview.

The initial release was published with Wrangler. Use a separate `XDG_CONFIG_HOME` for this Cloudflare account if your default Wrangler login belongs to another account. Apply the same `XDG_CONFIG_HOME` to both login and deploy commands. Deployment permissions must include `workers_scripts:write`, `workers:write`, `workers_routes:write`, `zone:read`, `account:read`, and `user:read`. The account ID in `wrangler.jsonc` prevents deployment to a different account.

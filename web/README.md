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

The initial release was uploaded through the Cloudflare dashboard. The existing local Wrangler login belongs to another account: sign into the account above before deploying from the CLI. Alternatively, use Workers → codex-pet-bar → Deployments → Upload new version to upload `web/build`.

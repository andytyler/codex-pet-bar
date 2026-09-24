# Codex Pet Bar website

The homepage and `/landing/` use the chosen Pet Bar design. Earlier directions are preserved under `design/archive/` and are not deployed.

```sh
bun install --frozen-lockfile
bun run dev
```

Validate the production deployment with its GitHub Pages base path:

```sh
bun run check
BASE_PATH=/codex-pet-bar bun run build
BASE_PATH=/codex-pet-bar bun run test
```

GitHub Actions publishes `web/build` to https://andytyler.github.io/codex-pet-bar/ after a successful main-branch build. The native application is distributed through GitHub Releases and Homebrew.

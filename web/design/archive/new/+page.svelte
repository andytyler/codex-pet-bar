<script lang="ts">
  import { onMount } from "svelte";
  import PetStrip from "$lib/components/pet-strip.svelte";
  import SpriteCell from "$lib/components/sprite-cell.svelte";

  const installCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";
  const installSteps = installCommand.split("\n");

  let copied = $state(false);
  let resetTimer: ReturnType<typeof setTimeout> | undefined;
  let now = $state("--:--");
  let mounted = $state(false);
  let pageVisible = $state(true);
  let activeMenu = $state<string | null>(null);
  let clockInterval: ReturnType<typeof setInterval> | undefined;

  const tickClock = () => {
    const d = new Date();
    const h = d.getHours();
    const m = d.getMinutes();
    const ampm = h < 12 ? "AM" : "PM";
    const hh = ((h + 11) % 12) + 1;
    now = `${hh}:${String(m).padStart(2, "0")} ${ampm}`;
  };

  const stopClock = () => {
    if (clockInterval === undefined) return;
    clearInterval(clockInterval);
    clockInterval = undefined;
  };

  const startClock = () => {
    tickClock();
    if (clockInterval === undefined) {
      clockInterval = setInterval(tickClock, 30_000);
    }
  };

  const syncPageVisibility = () => {
    pageVisible = document.visibilityState === "visible";
    if (pageVisible) startClock();
    else stopClock();
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(installCommand);
      copied = true;
      clearTimeout(resetTimer);
      resetTimer = setTimeout(() => (copied = false), 1800);
    } catch {
      copied = false;
    }
  };

  onMount(() => {
    mounted = true;
    syncPageVisibility();
    return () => {
      stopClock();
      clearTimeout(resetTimer);
    };
  });

  const PET = {
    goblin:  "/pets/goblin.webp",
    tock:    "/pets/tock.webp",
    boo:     "/pets/boo.webp",
    ajt:     "/pets/ajt.webp",
    clippy:  "/pets/clippy.webp",
    grumble: "/pets/grumble.webp",
  } as const;

  // Pet rosters for each strip. PetStrip handles direction + delay distribution.
  const barRunners = [
    { src: PET.goblin,  dir: "right" as const },
    { src: PET.tock,    dir: "left"  as const },
    { src: PET.boo,     dir: "right" as const },
    { src: PET.ajt,     dir: "left"  as const },
  ];
  const readmeRunners  = [{ src: PET.goblin, dir: "right" as const }, { src: PET.clippy, dir: "left" as const }];
  const petsRunners    = [{ src: PET.ajt,    dir: "left"  as const }, { src: PET.boo,    dir: "right" as const }];
  const termRunners    = [{ src: PET.grumble,dir: "right" as const }];
  const bhvRunners     = [{ src: PET.tock,   dir: "right" as const }, { src: PET.boo,    dir: "left" as const }];
  const aboutRunners   = [{ src: PET.clippy, dir: "left"  as const }];

  // Real pets shipped in the app, each shown in its idle pose in the Pets folder.
  const pets = [
    { name: "Goblin",  file: "goblin.pet",  src: PET.goblin,  tag: "Mascot" },
    { name: "Tock",    file: "tock.pet",    src: PET.tock,    tag: "Timekeeper" },
    { name: "Boo",     file: "boo.pet",     src: PET.boo,     tag: "Lurker" },
    { name: "AJT",     file: "ajt.pet",     src: PET.ajt,     tag: "Maker" },
    { name: "Clippy",  file: "clippy.pet",  src: PET.clippy,  tag: "Helper" },
    { name: "Grumble", file: "grumble.pet", src: PET.grumble, tag: "Sentry" },
  ];

  // Hook → state → pet, with the matching animation row driven by SpriteCell.
  const behaviors = [
    { hook: "PermissionRequest", state: "approval_pending", pet: "Boo",     anim: "waiting" as const, src: PET.boo,     msg: "Holds the flag until you decide." },
    { hook: "PreToolUse",        state: "tool_started",     pet: "Goblin",  anim: "running" as const, src: PET.goblin,  msg: "Trots while Codex is editing." },
    { hook: "PostToolUse",       state: "stopped",          pet: "Tock",    anim: "idle"    as const, src: PET.tock,    msg: "Settles with a small celebration." },
  ];

  const aboutFacts = [
    { k: "Local first",     v: "Hooks read local Codex activity and write status under ~/.codex." },
    { k: "No cloud",        v: "Pure menu-bar utility. No account, no telemetry, no server." },
    { k: "Hackable",        v: "Pets are filesystem packages — inspect, fork, replace." },
    { k: "MIT licensed",    v: "Open source by Andy Tyler. PRs welcome." },
  ];
</script>

<svelte:document onvisibilitychange={syncPageVisibility} />

<svelte:head>
  <title>Codex Pet Bar — Finder</title>
  <meta property="og:title" content="Codex Pet Bar" />
  <meta property="og:description" content="Tiny pets for your menu bar that react to Codex hooks." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-finder.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:alt" content="Codex Pet Bar Finder-style social card with tiny menu-bar pets and the text Codex, with company." />
  <meta name="twitter:image" content="/artwork/open-graph/codex-pet-bar-og-finder.png" />
  <meta name="twitter:image:alt" content="Codex Pet Bar Finder-style social card with tiny menu-bar pets and the text Codex, with company." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@400..700&family=JetBrains+Mono:ital,wght@0,300..800;1,300..800&family=Newsreader:ital,opsz,wght@0,6..72,200..800;1,6..72,200..800&display=swap"
    rel="stylesheet" />
</svelte:head>

<!-- ░░ DESKTOP ░░ -->
<div class={["desktop", { mounted, inactive: !pageVisible }]}>
  <!-- ╔ Menu Bar ╗ -->
  <nav class="menubar" aria-label="System menu">
    <div class="mb-left">
      <button
        type="button"
        class="apple"
        onmouseenter={() => (activeMenu = "apple")}
        onmouseleave={() => (activeMenu = null)}
        aria-label="Apple menu">
        <span class="apple-glyph">●</span>
      </button>
      <button type="button" class="mb-item">Finder</button>
      <button type="button" class="mb-item">File</button>
      <button type="button" class="mb-item">Edit</button>
      <button
        type="button"
        class="mb-item active"
        onmouseenter={() => (activeMenu = "pets")}
        onmouseleave={() => (activeMenu = null)}>
        Pets ▾
      </button>
      <button type="button" class="mb-item">Window</button>
      <button type="button" class="mb-item">Help</button>

      {#if activeMenu === "pets"}
        <div class="mb-dropdown" role="menu">
          <a href="#pets" class="mb-dd-item">Open Pets Folder<span class="kbd">⌘O</span></a>
          <a href="#install" class="mb-dd-item">Install…<span class="kbd">⌘I</span></a>
          <a href="#behaviors" class="mb-dd-item">View Behaviours<span class="kbd">⌘B</span></a>
          <div class="mb-dd-sep"></div>
          <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer" class="mb-dd-item">
            Source on GitHub ↗
          </a>
        </div>
      {/if}
    </div>

    <div class="mb-right">
      <img src="/states/listening-ear.png" alt="" class="mb-petlive" />
      <span class="mb-meta">3 pets running</span>
      <span class="mb-divider"></span>
      <span class="mb-bat" title="Battery"><span class="mb-bat-fill"></span></span>
      <span class="mb-wifi" aria-hidden="true">
        <span></span><span></span><span></span>
      </span>
      <span class="mb-clock">{now}</span>
    </div>

    <div class="mb-pets" aria-hidden="true">
      <PetStrip pets={barRunners} height={32} bordered={false} active={pageVisible} />
    </div>
  </nav>

  <!-- ╔ Desktop background — dither, sticky-notes, icons ╗ -->
  <div class="desktop-bg" aria-hidden="true"></div>

  <!-- Desktop icons in the corners -->
  <div class="dt-icon dt-icon-app" aria-hidden="true">
    <img src="/artwork/codex-pet-bar-icon.png" alt="" />
    <span>codex-pet-bar.app</span>
  </div>
  <div class="dt-icon dt-icon-trash" aria-hidden="true">
    <div class="trash-can"><span></span></div>
    <span>Trash</span>
  </div>

  <!-- Sticky note pinned to desktop -->
  <aside class="sticky" aria-label="Sticky note">
    <p class="sticky-h">a note from andy —</p>
    <p>
      build a tiny pet that watches my agent.<br />
      friends &gt; notifications.<br />
      keep it local. keep it weird.
    </p>
    <p class="sticky-sig">— ajt</p>
  </aside>

  <!-- ╔ Window stack ╗ -->
  <main class="window-stack">
    <!-- README WINDOW (hero) -->
    <section class="win win-readme" id="top" style="--tilt: -0.4deg;">
      <header class="titlebar">
        <button type="button" class="tb-btn close" aria-label="Close"></button>
        <button type="button" class="tb-btn zoom"  aria-label="Zoom"></button>
        <div class="tb-stripes"></div>
        <div class="tb-title">📖 ReadMe — Codex Pet Bar.app</div>
        <div class="tb-stripes"></div>
      </header>

      <div class="win-petrail">
        <PetStrip pets={readmeRunners} height={28} active={pageVisible} />
      </div>

      <div class="win-body win-body-hero">
        <div class="hero-left">
          <span class="kicker">macOS Menu-Bar Companion</span>
          <h1 class="hero-h1">
            <span>Codex,</span>
            <span class="hero-em">with company.</span>
          </h1>
          <p class="hero-lede">
            Tiny pets that listen to local Codex activity, react to approvals,
            and make each thread legible at a glance — right where your eyes already are.
          </p>

          <div class="hero-actions">
            <a class="btn btn-primary" href="#install">
              <span class="btn-arrow">▶</span>
              Install from source
            </a>
            <a class="btn btn-ghost" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
              ★ Star on GitHub
            </a>
          </div>

          <ul class="hero-stats">
            <li><span class="stat-n">0</span><span class="stat-l">background services</span></li>
            <li><span class="stat-n">∞</span><span class="stat-l">pets you can write</span></li>
            <li><span class="stat-n">~/.codex</span><span class="stat-l">where state lives</span></li>
          </ul>
        </div>

        <div class="hero-right">
          <div class="hero-vitrine">
            <img src="/artwork/codex-pet-bar-hero-trans.png" alt="A lineup of Codex menu-bar pets" />
          </div>
          <p class="hero-cap">▸ Fig. A — assorted specimens, at rest</p>
        </div>
      </div>
    </section>

    <!-- PETS FOLDER WINDOW -->
    <section class="win win-pets" id="pets" style="--tilt: 0.5deg;">
      <header class="titlebar">
        <button type="button" class="tb-btn close" aria-label="Close"></button>
        <button type="button" class="tb-btn zoom"  aria-label="Zoom"></button>
        <div class="tb-stripes"></div>
        <div class="tb-title">📁 Pets — {pets.length} items, 18.4 MB</div>
        <div class="tb-stripes"></div>
      </header>

      <div class="win-petrail">
        <PetStrip pets={petsRunners} height={28} active={pageVisible} />
      </div>

      <div class="finder-toolbar">
        <span class="tool-tab">Icon</span>
        <span class="tool-tab dim">List</span>
        <span class="tool-tab dim">Column</span>
        <span class="tool-sep"></span>
        <span class="tool-path mono">~/.codex/pets/</span>
        <span class="tool-spacer"></span>
        <span class="tool-tab dim">Sort: Name ▾</span>
      </div>

      <div class="win-body pets-grid">
        {#each pets as p, i (p.file)}
          <button type="button" class="pet-tile" style={`animation-delay:${i * 60}ms`}>
            <div class="pet-thumb">
              <SpriteCell src={p.src} state="idle" size={80} phase={i / pets.length} active={pageVisible} />
            </div>
            <div class="pet-name">{p.file}</div>
            <div class="pet-tag">{p.tag}</div>
          </button>
        {/each}
      </div>

      <footer class="win-status">
        <span>{pets.length} of {pets.length} selected</span>
        <span class="dim">▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒</span>
        <span>2.1 GB free</span>
      </footer>
    </section>

    <!-- TERMINAL / INSTALL WINDOW -->
    <section class="win win-term" id="install" style="--tilt: -0.6deg;">
      <header class="titlebar dark">
        <button type="button" class="tb-btn close" aria-label="Close"></button>
        <button type="button" class="tb-btn zoom"  aria-label="Zoom"></button>
        <div class="tb-stripes dark"></div>
        <div class="tb-title">▣ Terminal — install.sh — 80×24</div>
        <div class="tb-stripes dark"></div>
      </header>

      <div class="win-petrail">
        <PetStrip pets={termRunners} height={28} variant="dark" active={pageVisible} />
      </div>

      <div class="win-body term-body">
        <div class="term-screen">
          <p class="term-line dim">Last login: today on tty/codex</p>
          <p class="term-line dim">Welcome to the Pet Bar. Three lines from here.</p>
          <p class="term-line">&nbsp;</p>
          {#each installSteps as cmd, i (cmd)}
            <p class="term-line" style={`animation-delay:${300 + i * 220}ms`}>
              <span class="term-prompt">andy@studio</span><span class="term-sep">:</span><span class="term-cwd">~</span><span class="term-sep">$</span>
              <span class="term-cmd">{cmd}</span>
            </p>
          {/each}
          <p class="term-line live">
            <span class="term-prompt">andy@studio</span><span class="term-sep">:</span><span class="term-cwd">~</span><span class="term-sep">$</span>
            <span class="term-cursor">▌</span>
          </p>
        </div>

        <div class="term-actions">
          <button type="button" class="btn btn-primary" onclick={copy}>
            {copied ? "✓  Copied" : "⌘C  Copy install"}
          </button>
          <a class="btn btn-ghost" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
            man codex-pet-bar →
          </a>
          <span class="term-note">Requires macOS 13+ and a working <span class="mono">codex</span>.</span>
        </div>
      </div>
    </section>

    <!-- BEHAVIORS WINDOW -->
    <section class="win win-behaviors" id="behaviors" style="--tilt: 0.3deg;">
      <header class="titlebar">
        <button type="button" class="tb-btn close" aria-label="Close"></button>
        <button type="button" class="tb-btn zoom"  aria-label="Zoom"></button>
        <div class="tb-stripes"></div>
        <div class="tb-title">⚯ Behaviours — hook → state → pet</div>
        <div class="tb-stripes"></div>
      </header>

      <div class="win-petrail">
        <PetStrip pets={bhvRunners} height={28} active={pageVisible} />
      </div>

      <div class="win-body">
        <table class="bh-table">
          <thead>
            <tr>
              <th>Hook</th>
              <th>State</th>
              <th>Pet</th>
              <th class="bh-th-wide">What it does</th>
              <th class="bh-th-illus" aria-label="Illustration"></th>
            </tr>
          </thead>
          <tbody>
            {#each behaviors as b, i (b.hook)}
              <tr class="bh-row">
                <td class="mono"><span class="bh-pill bh-pill-hook">{b.hook}</span></td>
                <td class="mono dim">{b.state}</td>
                <td><strong>{b.pet}</strong></td>
                <td class="bh-msg">{b.msg}</td>
                <td class="bh-illus">
                  <SpriteCell src={b.src} state={b.anim} size={56} phase={i / behaviors.length} active={pageVisible} />
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>

    <!-- ABOUT WINDOW -->
    <section class="win win-about" style="--tilt: -0.3deg;">
      <header class="titlebar">
        <button type="button" class="tb-btn close" aria-label="Close"></button>
        <button type="button" class="tb-btn zoom"  aria-label="Zoom"></button>
        <div class="tb-stripes"></div>
        <div class="tb-title">ⓘ Get Info — codex-pet-bar.app</div>
        <div class="tb-stripes"></div>
      </header>

      <div class="win-petrail">
        <PetStrip pets={aboutRunners} height={28} active={pageVisible} />
      </div>

      <div class="win-body about-body">
        <div class="about-icon">
          <img src="/artwork/codex-pet-bar-icon.png" alt="App icon" />
          <p>codex-pet-bar.app</p>
          <p class="dim mono">v0.1.2 — MIT</p>
        </div>
        <dl class="about-dl">
          {#each aboutFacts as f (f.k)}
            <div class="about-row">
              <dt>{f.k}</dt>
              <dd>{f.v}</dd>
            </div>
          {/each}
        </dl>
      </div>
    </section>
  </main>

  <!-- ╔ MOTD ticker ╗ -->
  <footer class="motd" aria-label="System log">
    <div class="motd-tag">SYS</div>
    <div class="motd-track">
      <p>
        ▸ codex-pet-bar.app loaded · listening on ~/.codex ·
        approvals queue clear · last build OK ·
        coffee level: critical · made in 🇬🇧 by
        <a href="https://ajt.dev" target="_blank" rel="noreferrer">ajt.dev</a> ·
        MIT licensed · ★ on
        <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">github.com/andytyler/codex-pet-bar</a> ·
        codex-pet-bar.app loaded · listening on ~/.codex ·
        approvals queue clear · last build OK ·
      </p>
    </div>
  </footer>
</div>

<style>
  /* ============================================================
     DESKTOP — A reimagined Codex Pet Bar landing as a Mac desktop
     ============================================================ */

  .desktop {
    --paper:      #f4efe6;
    --desk:       #c8c2b0;
    --desk-2:     #b8b29e;
    --ink:        #1a1814;
    --ink-soft:   #4a463e;
    --ink-faint:  #7a7568;
    --rule:       #1a1814;
    --window:     #fbf9f4;
    --window-2:   #efece4;
    --accent:     #ff5a3c;       /* hot coral */
    --accent-2:   #ffe05a;       /* highlighter */
    --shadow:     #1a1814;
    --term-bg:    #14110d;
    --term-fg:    #e9e2d0;
    --term-dim:   #7c7466;
    --term-prompt:#ff8a5b;

    --font-ui:    "Pixelify Sans", "Chicago", "Geneva", system-ui, sans-serif;
    --font-body:  "Newsreader", Georgia, serif;
    --font-mono:  "JetBrains Mono", "SF Mono", ui-monospace, monospace;

    position: relative;
    min-height: 100vh;
    color: var(--ink);
    font-family: var(--font-body);
    overflow-x: hidden;
    padding-top: 32px; /* leave room for menubar */
  }
  :global(body:has(.desktop)) {
    background: var(--desk) !important;
    margin: 0;
  }

  /* ░░ Desktop tile pattern ░░ */
  .desktop-bg {
    position: fixed;
    inset: 32px 0 0 0;
    z-index: 0;
    pointer-events: none;
    background-color: #c8c2b0;
    background-image:
      /* hard 50% dither */
      radial-gradient(rgba(26, 24, 20, 0.18) 1px, transparent 1.4px),
      radial-gradient(rgba(255, 250, 240, 0.4) 1px, transparent 1.4px);
    background-size: 4px 4px, 4px 4px;
    background-position: 0 0, 2px 2px;
  }

  /* ░░ MENUBAR ░░ */
  .menubar {
    position: fixed;
    top: 0; left: 0; right: 0;
    height: 32px;
    background: var(--window);
    border-bottom: 1.5px solid var(--ink);
    display: flex; align-items: stretch; justify-content: space-between;
    font-family: var(--font-ui);
    font-size: 14px;
    z-index: 100;
    box-shadow: 0 1px 0 rgba(0,0,0,0.06);
  }
  .mb-left, .mb-right { display: flex; align-items: stretch; position: relative; z-index: 2; }
  .mb-right { padding-right: 8px; gap: 10px; align-items: center; }

  /* Menu-bar pet rail sits behind menu items (which set z-index: 2). */
  .mb-pets {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 1;
  }
  .mb-pets :global(.strip) { background: transparent; }
  .apple, .mb-item {
    appearance: none;
    background: transparent;
    border: 0;
    padding: 0 12px;
    font-family: var(--font-ui);
    font-size: 14px;
    color: var(--ink);
    cursor: pointer;
    line-height: 32px;
    transition: background 80ms ease;
    position: relative;
  }
  .apple { padding-left: 14px; padding-right: 14px; }
  .apple-glyph {
    display: inline-block;
    width: 11px; height: 11px;
    border-radius: 50%;
    background: var(--ink);
  }
  .mb-item:hover, .mb-item.active:hover,
  .apple:hover { background: var(--ink); color: var(--paper); }
  .apple:hover .apple-glyph { background: var(--paper); }

  .mb-dropdown {
    position: absolute;
    top: 32px;
    left: 246px;
    min-width: 240px;
    background: var(--window);
    border: 1.5px solid var(--ink);
    box-shadow: 4px 4px 0 rgba(26, 24, 20, 0.7);
    z-index: 200;
    padding: 4px 0;
  }
  /* Apple dropdown — anchored to the apple button so it doesn't slip behind the pet strip */
  .mb-left { z-index: 3; }
  .mb-dd-item {
    display: flex;
    justify-content: space-between;
    padding: 5px 14px;
    font-family: var(--font-ui);
    font-size: 13.5px;
    color: var(--ink);
    text-decoration: none;
  }
  .mb-dd-item:hover { background: var(--ink); color: var(--paper); }
  .mb-dd-sep { height: 1px; background: var(--ink-faint); margin: 4px 8px; }
  .kbd { color: var(--ink-faint); margin-left: 12px; }
  .mb-dd-item:hover .kbd { color: var(--paper); opacity: 0.7; }

  .mb-petlive {
    width: 22px; height: 22px;
    object-fit: contain;
    image-rendering: pixelated;
    animation: bob 2.4s ease-in-out infinite;
  }
  @keyframes bob {
    0%, 100% { transform: translateY(0) rotate(-2deg); }
    50%      { transform: translateY(-2px) rotate(2deg); }
  }
  .mb-meta { color: var(--ink-soft); font-size: 12.5px; }
  .mb-divider { width: 1px; height: 16px; background: var(--ink-faint); }
  .mb-bat {
    display: inline-block;
    width: 22px; height: 11px;
    border: 1.5px solid var(--ink);
    border-radius: 1px;
    position: relative;
  }
  .mb-bat::after {
    content: ""; position: absolute;
    right: -3px; top: 2px; width: 2px; height: 5px;
    background: var(--ink);
  }
  .mb-bat-fill {
    display: block;
    width: 80%; height: 100%;
    background: var(--ink);
  }
  .mb-wifi {
    display: inline-flex; align-items: flex-end; gap: 1.5px;
  }
  .mb-wifi span {
    width: 3px; background: var(--ink);
  }
  .mb-wifi span:nth-child(1) { height: 4px; }
  .mb-wifi span:nth-child(2) { height: 7px; }
  .mb-wifi span:nth-child(3) { height: 10px; }
  .mb-clock {
    font-family: var(--font-ui);
    font-size: 13.5px;
    color: var(--ink);
    min-width: 70px;
    text-align: right;
  }

  /* ░░ Desktop icons ░░ */
  .dt-icon {
    position: fixed;
    z-index: 1;
    width: 88px;
    text-align: center;
    font-family: var(--font-ui);
    font-size: 12px;
    color: var(--ink);
    text-shadow: 1px 1px 0 var(--paper);
    pointer-events: none;
  }
  .dt-icon img {
    width: 56px; height: 56px;
    margin: 0 auto 4px;
    display: block;
    filter: drop-shadow(2px 2px 0 rgba(0,0,0,0.25));
    image-rendering: -webkit-optimize-contrast;
  }
  .dt-icon-app { top: 56px; right: 28px; }
  .dt-icon-trash { bottom: 72px; right: 28px; }
  .dt-icon-trash span:not(.trash-can span) { display: block; }
  .trash-can {
    width: 46px; height: 56px; margin: 0 auto 4px;
    border: 2px solid var(--ink);
    border-top: 0;
    border-radius: 0 0 6px 6px;
    background: var(--window);
    position: relative;
    box-shadow: 2px 2px 0 rgba(0,0,0,0.25);
  }
  .trash-can::before {
    content: "";
    position: absolute; left: -4px; right: -4px; top: -7px;
    height: 4px; background: var(--ink);
  }
  .trash-can::after {
    content: ""; position: absolute; left: 50%; top: -12px;
    transform: translateX(-50%);
    width: 14px; height: 5px;
    border: 2px solid var(--ink);
    border-bottom: 0;
    border-radius: 50% 50% 0 0;
  }
  .trash-can span {
    position: absolute; inset: 6px 4px;
    background: repeating-linear-gradient(90deg, transparent 0 4px, rgba(0,0,0,0.18) 4px 5px);
  }

  /* ░░ Sticky note ░░ */
  .sticky {
    position: fixed;
    top: 92px;
    left: 28px;
    width: 168px;
    padding: 14px 14px 10px;
    background: var(--accent-2);
    color: var(--ink);
    font-family: var(--font-body);
    font-size: 13px;
    line-height: 1.4;
    transform: rotate(-4deg);
    z-index: 1;
    box-shadow:
      2px 2px 0 rgba(0,0,0,0.05),
      4px 6px 16px rgba(0,0,0,0.25);
    border-radius: 1px;
  }
  .sticky::before {
    /* pin */
    content: "";
    position: absolute;
    top: -6px; left: 50%;
    transform: translateX(-50%);
    width: 12px; height: 12px;
    background: var(--accent);
    border-radius: 50%;
    box-shadow: 0 2px 4px rgba(0,0,0,0.3), inset -2px -2px 0 rgba(0,0,0,0.2);
  }
  .sticky p { margin: 0 0 6px; }
  .sticky-h { font-family: var(--font-ui); font-size: 13px; }
  .sticky-sig { text-align: right; font-style: italic; color: var(--ink-soft); }

  /* ░░ Window stack layout ░░ */
  .window-stack {
    position: relative;
    z-index: 2;
    max-width: 1100px;
    margin: 0 auto;
    padding: 40px clamp(16px, 4vw, 56px) 80px;
    display: flex;
    flex-direction: column;
    gap: clamp(40px, 6vw, 80px);
  }

  /* ░░ WINDOW chrome ░░ */
  .win {
    background: var(--window);
    border: 1.5px solid var(--ink);
    box-shadow: 6px 6px 0 var(--shadow);
    transform: rotate(var(--tilt, 0deg));
    transition: transform 220ms cubic-bezier(.2,.7,.2,1), box-shadow 220ms;
    scroll-margin-top: 60px;
    opacity: 0;
    animation: winIn 600ms cubic-bezier(.16,.84,.32,1) both;
  }
  .win:hover {
    transform: rotate(0deg) translate(-2px, -2px);
    box-shadow: 9px 9px 0 var(--shadow);
  }
  @keyframes winIn {
    from { opacity: 0; transform: rotate(var(--tilt, 0deg)) translateY(20px) scale(0.99); }
    to   { opacity: 1; transform: rotate(var(--tilt, 0deg)) translateY(0) scale(1); }
  }
  .win:nth-of-type(1) { animation-delay: 80ms; }
  .win:nth-of-type(2) { animation-delay: 160ms; }
  .win:nth-of-type(3) { animation-delay: 240ms; }
  .win:nth-of-type(4) { animation-delay: 320ms; }
  .win:nth-of-type(5) { animation-delay: 400ms; }

  /* Title bar with striped pattern */
  .titlebar {
    height: 24px;
    border-bottom: 1.5px solid var(--ink);
    display: grid;
    grid-template-columns: 24px 24px 1fr auto 1fr;
    align-items: center;
    background: var(--window);
    position: relative;
  }
  .titlebar.dark { background: var(--term-bg); border-bottom-color: var(--term-bg); }
  .tb-stripes {
    height: 14px;
    background-image: repeating-linear-gradient(
      to bottom,
      var(--ink) 0 1px,
      transparent 1px 3px
    );
    margin: 0 6px;
  }
  .tb-stripes.dark {
    background-image: repeating-linear-gradient(
      to bottom,
      var(--term-fg) 0 1px,
      transparent 1px 3px
    );
    opacity: 0.7;
  }
  .tb-btn {
    width: 14px; height: 14px;
    margin: 0 5px;
    appearance: none;
    background: var(--window);
    border: 1.5px solid var(--ink);
    cursor: pointer;
    padding: 0;
    transition: background 100ms;
  }
  .tb-btn:hover { background: var(--accent); }
  .titlebar.dark .tb-btn { background: var(--term-fg); border-color: var(--term-fg); }
  .titlebar.dark .tb-btn:hover { background: var(--accent); }
  .tb-title {
    font-family: var(--font-ui);
    font-size: 13.5px;
    text-align: center;
    color: var(--ink);
    padding: 0 14px;
    white-space: nowrap;
  }
  .titlebar.dark .tb-title { color: var(--term-fg); }

  .win-body { padding: clamp(20px, 3vw, 36px); }

  /* Thin pet rail under each titlebar; takes the strip component's own borders. */
  .win-petrail { position: relative; }

  /* ░░ HERO WINDOW ░░ */
  .win-body-hero {
    display: grid;
    grid-template-columns: 1.05fr 1fr;
    gap: clamp(20px, 4vw, 48px);
    align-items: center;
  }
  @media (max-width: 800px) {
    .win-body-hero { grid-template-columns: 1fr; }
  }
  .kicker {
    display: inline-block;
    font-family: var(--font-ui);
    font-size: 12px;
    padding: 4px 10px;
    background: var(--ink);
    color: var(--paper);
    letter-spacing: 0.04em;
    margin-bottom: 16px;
  }
  .hero-h1 {
    font-family: var(--font-body);
    font-weight: 600;
    font-size: clamp(48px, 8vw, 96px);
    line-height: 0.95;
    margin: 0 0 18px;
    letter-spacing: -0.02em;
  }
  .hero-h1 span { display: block; }
  .hero-em {
    font-style: italic;
    color: var(--accent);
    font-weight: 500;
  }
  .hero-lede {
    font-size: 17px;
    line-height: 1.55;
    color: var(--ink-soft);
    max-width: 44ch;
    margin: 0 0 24px;
  }
  .hero-actions {
    display: flex; gap: 10px; flex-wrap: wrap;
    margin-bottom: 28px;
  }
  .btn {
    appearance: none;
    border: 1.5px solid var(--ink);
    background: var(--window);
    color: var(--ink);
    font-family: var(--font-ui);
    font-size: 14px;
    padding: 10px 16px;
    cursor: pointer;
    text-decoration: none;
    display: inline-flex; align-items: center; gap: 8px;
    box-shadow: 3px 3px 0 var(--ink);
    transition: transform 100ms, box-shadow 100ms;
  }
  .btn:hover { transform: translate(-1px,-1px); box-shadow: 4px 4px 0 var(--ink); }
  .btn:active { transform: translate(2px,2px); box-shadow: 1px 1px 0 var(--ink); }
  .btn-primary { background: var(--accent); color: var(--paper); }
  .btn-primary .btn-arrow { font-size: 10px; }
  .btn-ghost   { background: var(--window); }

  .hero-stats {
    list-style: none; padding: 0; margin: 0;
    display: grid; grid-template-columns: repeat(3, 1fr);
    gap: 12px;
    border-top: 1.5px dashed var(--ink-faint);
    padding-top: 16px;
  }
  .hero-stats li { display: flex; flex-direction: column; gap: 2px; }
  .stat-n {
    font-family: var(--font-ui);
    font-size: 22px;
    color: var(--ink);
  }
  .stat-l {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .hero-right { text-align: center; }
  .hero-vitrine {
    position: relative;
    padding: 24px;
    background: var(--window-2);
    border: 1.5px solid var(--ink);
    box-shadow: inset 3px 3px 0 var(--window), inset -3px -3px 0 rgba(0,0,0,0.15);
  }
  .hero-vitrine img {
    width: 100%; height: auto;
    max-height: 360px; object-fit: contain;
    filter: drop-shadow(0 10px 14px rgba(0,0,0,0.18));
    animation: floaty 5.6s ease-in-out infinite;
  }
  @keyframes floaty {
    0%, 100% { transform: translateY(0) rotate(-1deg); }
    50%      { transform: translateY(-8px) rotate(1deg); }
  }
  .hero-cap {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-soft);
    margin: 12px 0 0;
  }

  /* ░░ PETS FOLDER ░░ */
  .finder-toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 12px;
    border-bottom: 1.5px solid var(--ink);
    background: var(--window-2);
    font-family: var(--font-ui);
    font-size: 12.5px;
  }
  .tool-tab {
    padding: 3px 10px;
    border: 1.5px solid var(--ink);
    background: var(--window);
    cursor: pointer;
  }
  .tool-tab.dim { color: var(--ink-faint); border-color: var(--ink-faint); background: transparent; }
  .tool-sep { width: 1px; height: 16px; background: var(--ink-faint); }
  .tool-path { color: var(--ink-soft); font-size: 12px; }
  .tool-spacer { flex: 1; }

  .pets-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(132px, 1fr));
    gap: 18px;
    padding: 26px;
  }
  .pet-tile {
    appearance: none;
    border: 0;
    background: transparent;
    cursor: pointer;
    display: flex; flex-direction: column; align-items: center; gap: 6px;
    padding: 10px 6px;
    font-family: var(--font-ui);
    color: var(--ink);
    opacity: 0;
    animation: fadeUp 480ms ease-out both;
    border-radius: 4px;
  }
  @keyframes fadeUp {
    from { opacity: 0; transform: translateY(8px); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .pet-tile:hover { background: var(--accent); color: var(--paper); }
  .pet-tile:hover .pet-tag { color: var(--paper); }
  .pet-thumb {
    width: 96px; height: 96px;
    display: flex; align-items: center; justify-content: center;
    background: var(--window-2);
    border: 1.5px solid var(--ink);
    box-shadow: 3px 3px 0 var(--ink);
    transition: transform 160ms;
  }
  .pet-tile:hover .pet-thumb { transform: translate(-2px,-2px) rotate(-3deg); box-shadow: 5px 5px 0 var(--ink); }
  .pet-name { font-size: 13.5px; }
  .pet-tag {
    font-family: var(--font-mono);
    font-size: 10.5px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .win-status {
    display: flex; justify-content: space-between; align-items: center; gap: 14px;
    padding: 5px 12px;
    border-top: 1.5px solid var(--ink);
    background: var(--window-2);
    font-family: var(--font-ui);
    font-size: 12px;
    color: var(--ink-soft);
  }
  .win-status .dim { color: var(--ink-faint); flex: 1; text-align: center; overflow: hidden; white-space: nowrap; }

  /* ░░ TERMINAL ░░ */
  .win-term {
    --window: var(--term-bg);
    background: var(--term-bg);
    color: var(--term-fg);
  }
  .term-body { padding: 0; }
  .term-screen {
    background: var(--term-bg);
    color: var(--term-fg);
    font-family: var(--font-mono);
    font-size: 14px;
    line-height: 1.7;
    padding: 22px 24px;
    min-height: 240px;
    position: relative;
  }
  .term-screen::before {
    /* scanlines */
    content: ""; position: absolute; inset: 0;
    background: repeating-linear-gradient(to bottom, rgba(255,255,255,0.03) 0 1px, transparent 1px 3px);
    pointer-events: none;
  }
  .term-line {
    margin: 0;
    opacity: 0;
    animation: typeIn 200ms ease-out forwards;
  }
  .term-line.live { animation: none; opacity: 1; }
  .term-line.dim { color: var(--term-dim); }
  @keyframes typeIn {
    from { opacity: 0; transform: translateY(2px); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .term-prompt { color: var(--term-prompt); }
  .term-sep    { color: var(--term-dim); margin: 0 2px; }
  .term-cwd    { color: var(--accent-2); }
  .term-cmd    { color: var(--term-fg); margin-left: 6px; }
  .term-cursor {
    color: var(--term-fg);
    margin-left: 4px;
    animation: cursorBlink 1060ms steps(1, end) infinite;
  }
  @keyframes cursorBlink {
    0%, 49% { opacity: 1; }
    50%, 100% { opacity: 0; }
  }

  .term-actions {
    display: flex; align-items: center; flex-wrap: wrap; gap: 10px;
    padding: 14px 18px;
    background: #1f1c16;
    border-top: 1.5px solid #2a2620;
  }
  .term-actions .btn { box-shadow: 3px 3px 0 #000; border-color: #000; }
  .term-actions .btn-ghost { background: var(--term-bg); color: var(--term-fg); border-color: var(--term-fg); }
  .term-note {
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--term-dim);
    margin-left: auto;
  }

  /* ░░ BEHAVIORS TABLE ░░ */
  .bh-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
  }
  .bh-table th {
    text-align: left;
    font-family: var(--font-ui);
    font-size: 11.5px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--ink-soft);
    padding: 10px 12px;
    border-bottom: 1.5px solid var(--ink);
    background: var(--window-2);
  }
  .bh-table td {
    padding: 14px 12px;
    border-bottom: 1px dashed var(--ink-faint);
    vertical-align: middle;
  }
  .bh-row:hover { background: var(--window-2); }
  .bh-th-illus { width: 64px; }
  .bh-msg { font-family: var(--font-body); font-size: 16px; line-height: 1.4; }
  .bh-illus { text-align: center; }
  .bh-pill {
    display: inline-block;
    padding: 3px 8px;
    border: 1.5px solid var(--ink);
    background: var(--accent-2);
    color: var(--ink);
    font-size: 12px;
  }
  .bh-pill-hook { background: var(--accent-2); }
  .dim { color: var(--ink-faint); }
  .mono { font-family: var(--font-mono); font-size: 12.5px; }

  /* ░░ ABOUT ░░ */
  .about-body {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 28px;
    align-items: start;
  }
  @media (max-width: 640px) {
    .about-body { grid-template-columns: 1fr; }
  }
  .about-icon { text-align: center; }
  .about-icon img {
    width: 128px; height: 128px;
    image-rendering: -webkit-optimize-contrast;
    filter: drop-shadow(3px 3px 0 rgba(0,0,0,0.25));
    margin-bottom: 10px;
  }
  .about-icon p { margin: 2px 0; font-family: var(--font-ui); font-size: 13.5px; }
  .about-dl { margin: 0; }
  .about-row {
    display: grid;
    grid-template-columns: 160px 1fr;
    gap: 16px;
    padding: 12px 0;
    border-bottom: 1px dashed var(--ink-faint);
  }
  .desktop.inactive * {
    animation-play-state: paused !important;
  }
  .about-row:first-child { padding-top: 0; }
  .about-row:last-child  { border-bottom: 0; }
  .about-row dt {
    font-family: var(--font-ui);
    font-size: 14px;
    color: var(--ink);
  }
  .about-row dd {
    margin: 0;
    color: var(--ink-soft);
    font-size: 15px;
    line-height: 1.45;
  }

  /* ░░ MOTD TICKER ░░ */
  .motd {
    position: fixed;
    left: 0; right: 0; bottom: 0;
    height: 26px;
    background: var(--ink);
    color: var(--paper);
    display: flex; align-items: center;
    border-top: 1.5px solid var(--ink);
    font-family: var(--font-mono);
    font-size: 12px;
    z-index: 50;
    overflow: hidden;
  }
  .motd-tag {
    background: var(--accent);
    color: var(--paper);
    padding: 0 10px;
    line-height: 26px;
    font-family: var(--font-ui);
    font-size: 12.5px;
    letter-spacing: 0.06em;
    flex-shrink: 0;
  }
  .motd-track {
    overflow: hidden;
    white-space: nowrap;
    flex: 1;
  }
  .motd-track p {
    display: inline-block;
    padding-left: 100%;
    margin: 0;
    animation: marquee 38s linear infinite;
  }
  .motd-track a {
    color: var(--accent-2);
    text-decoration: none;
  }
  @keyframes marquee {
    from { transform: translateX(0); }
    to   { transform: translateX(-100%); }
  }

  /* ░░ Hide desktop icons & sticky on small screens (room) ░░ */
  @media (max-width: 1180px) {
    .dt-icon-app { right: 8px; top: 44px; }
    .dt-icon-trash { right: 8px; bottom: 56px; }
  }
  @media (max-width: 900px) {
    .sticky, .dt-icon { display: none; }
  }
  @media (prefers-reduced-motion: reduce) {
    .win, .hero-vitrine img, .mb-petlive, .motd-track p, .pet-tile, .term-line, .term-cursor {
      animation: none !important;
      transform: none !important;
      opacity: 1 !important;
    }
    .mb-pets, .win-petrail { display: none; }
  }
</style>

<script lang="ts">
  import { onMount } from "svelte";

  const installCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";
  const installLines = installCommand.split("\n");

  let copied = $state(false);
  let resetTimer: ReturnType<typeof setTimeout> | undefined;
  let mounted = $state(false);
  let scrolled = $state(false);
  let liveIdx = $state(0);
  let liveTime = $state("--:--");

  type LiveStep = { label: string; img: string; tone: string };
  const liveSteps: LiveStep[] = [
    { label: "listening",        img: "/artwork/moments/approval-rock.png",  tone: "blue"   },
    { label: "running tools…",   img: "/artwork/moments/running-flame.png",  tone: "amber"  },
    { label: "thread complete",  img: "/artwork/moments/completed-ajt.png",  tone: "green"  },
  ];
  const live = $derived(liveSteps[liveIdx]);

  const moments = [
    {
      no: "01",
      eyebrow: "PERMISSION REQUEST",
      title: "When Codex pauses, the pet shows up.",
      body: "Approvals stop being modal interruptions and become something you can see at a glance — a small, deliberate stillness in your menu bar.",
      hook: "PermissionRequest · permission_requested",
      img: "/artwork/moments/approval-rock.png",
      pet: "Rock",
      tone: "blue",
    },
    {
      no: "02",
      eyebrow: "TOOL USE",
      title: "When tools run, the pet runs with them.",
      body: "PreToolUse and edit events turn into motion. The pet is jogging while Codex is shelling, searching, or writing — never a spinner, never silent.",
      hook: "PreToolUse · tool_started",
      img: "/artwork/moments/running-flame.png",
      pet: "Flame",
      tone: "amber",
    },
    {
      no: "03",
      eyebrow: "THREAD COMPLETE",
      title: "When the work ends, the pet celebrates.",
      body: "Successful results and stops settle the pet back down — with a small celebratory beat when the thread is done. Closure that a notification can't deliver.",
      hook: "PostToolUse · stopped",
      img: "/artwork/moments/completed-ajt.png",
      pet: "AJT",
      tone: "green",
    },
  ];

  const features = [
    {
      glyph: "○",
      h: "Local first",
      t: "Hooks read your local Codex activity and write small status updates beneath ~/.codex. Nothing leaves your machine.",
    },
    {
      glyph: "△",
      h: "No background cloud",
      t: "A macOS menu-bar utility — not a hosted service. There is no account, no server, no telemetry pipe.",
    },
    {
      glyph: "□",
      h: "Hackable pets",
      t: "Each pet is a package on disk. Inspect them, fork them, or commission your own — the format is yours.",
    },
    {
      glyph: "✦",
      h: "Open source",
      t: "Made by Andy Tyler under the MIT licence, for people who like to hack on their tooling.",
    },
  ];

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

  const tickClock = () => {
    const d = new Date();
    const h = d.getHours();
    const m = d.getMinutes();
    liveTime = `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
  };

  onMount(() => {
    mounted = true;
    tickClock();
    const ci = setInterval(tickClock, 30_000);
    const li = setInterval(() => {
      liveIdx = (liveIdx + 1) % liveSteps.length;
    }, 2600);
    const onScroll = () => {
      scrolled = window.scrollY > 24;
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      clearInterval(ci);
      clearInterval(li);
      clearTimeout(resetTimer);
    };
  });
</script>

<svelte:head>
  <title>Codex Pet Bar — Tiny menu-bar pets for your Codex agent</title>
  <meta property="og:title" content="Codex Pet Bar" />
  <meta property="og:description" content="Tiny pets that listen to local Codex activity, react to approvals, and make each thread legible at a glance." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-original.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:alt" content="Codex Pet Bar social card with tiny pets watching code activity in the menu bar." />
  <meta name="twitter:image" content="/artwork/open-graph/codex-pet-bar-og-original.png" />
  <meta name="twitter:image:alt" content="Codex Pet Bar social card with tiny pets watching code activity in the menu bar." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Inter+Tight:ital,opsz,wght@0,14..32,200..900;1,14..32,200..900&family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400..700&display=swap"
    rel="stylesheet" />
</svelte:head>

<div class="root" class:mounted>
  <!-- ░░ Atmosphere ░░ -->
  <div class="atmosphere" aria-hidden="true">
    <div class="halo halo-1"></div>
    <div class="halo halo-2"></div>
    <div class="grain"></div>
  </div>

  <!-- ░░ NAV ░░ -->
  <nav class="nav" class:scrolled aria-label="Primary">
    <div class="nav-inner">
      <a class="brand" href="#top">
        <img src="/artwork/codex-pet-bar-icon.png" alt="" />
        <span><strong>Codex Pet Bar</strong></span>
      </a>
      <ul class="nav-links">
        <li><a href="#install">Install</a></li>
        <li><a href="#moments">Moments</a></li>
        <li><a href="#why">Why</a></li>
      </ul>
      <div class="nav-actions">
        <a class="nav-gh" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
          <span class="gh-star">★</span> GitHub
        </a>
      </div>
    </div>
  </nav>

  <!-- ░░ HERO ░░ -->
  <section class="hero" id="top">
    <!-- live menubar -->
    <div class="livedemo">
      <div class={`livedemo-bar tone-${live.tone}`}>
        <span class="ld-apple"></span>
        <span class="ld-app">codex</span>
        <span class="ld-spacer"></span>
        <span class="ld-status">
          <span class="ld-dot"></span>
          <span class="ld-label">{live.label}</span>
        </span>
        <span class="ld-petwrap">
          {#each liveSteps as s, i}
            <img src={s.img} alt="" class="ld-pet" class:active={i === liveIdx} />
          {/each}
        </span>
        <span class="ld-meta">●●○</span>
        <span class="ld-clock">{liveTime}</span>
      </div>
      <p class="livedemo-cap">— your menu bar, with a friend in it</p>
    </div>

    <div class="hero-content">
      <span class="kicker">
        <span class="kicker-dot"></span>
        A <em>macOS</em> menu-bar companion for Codex
      </span>

      <h1 class="hero-title">
        <span class="line line-1">Codex Pet Bar.</span>
        <span class="line line-2">
          Tiny pets that <em>watch</em>
        </span>
        <span class="line line-3">your code with you.</span>
      </h1>

      <p class="hero-lede">
        Drop a small 3D creature into your menu bar. It listens to local Codex activity —
        approvals, tool runs, completions — and turns the lifecycle of every thread into
        something you can <em>see</em>, not another notification.
      </p>

      <div class="hero-actions">
        <a class="btn btn-primary" href="#install">
          <span class="btn-arrow">↓</span>
          Install
        </a>
        <a class="btn btn-ghost" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
          <span class="gh-star">★</span>
          Star on GitHub
        </a>
      </div>

      <ul class="hero-specs">
        <li><span class="dot ok"></span>macOS 13+</li>
        <li>MIT licensed</li>
        <li>~4&nbsp;MB · zero background services</li>
      </ul>
    </div>

    <!-- hero stage -->
    <div class="stage">
      <div class="stage-glow" aria-hidden="true"></div>
      <div class="stage-base" aria-hidden="true"></div>
      <img
        src="/artwork/codex-pet-bar-hero-trans.png"
        alt="A line-up of Codex Pet Bar pets"
        class="stage-img" />
      <div class="stage-pin pin-a"><span>★ 1st EDITION</span></div>
      <div class="stage-pin pin-b"><span>3 PETS ON DUTY</span></div>
    </div>
  </section>

  <!-- ░░ INSTALL ░░ -->
  <section class="install" id="install">
    <header class="section-head">
      <span class="section-eyebrow">INSTALLATION</span>
      <h2 class="section-title">Three lines from <em>nothing</em> to a pet.</h2>
      <p class="section-lede">
        Clone the repo, run the installer. We'll set up the hooks under
        <code class="inline-code">~/.codex</code> and put the pet bar in your menu.
      </p>
    </header>

    <div class="term-frame">
      <header class="term-head">
        <div class="term-lights" aria-hidden="true">
          <span class="tl tl-r"></span>
          <span class="tl tl-y"></span>
          <span class="tl tl-g"></span>
        </div>
        <span class="term-title">terminal — install.sh — 80 × 24</span>
        <button type="button" class="term-copy" onclick={copy} aria-live="polite">
          {copied ? "✓ Copied" : "Copy"}
        </button>
      </header>
      <pre class="term-body"><code>{#each installLines as line, i}<span class="term-row" style={`animation-delay:${i * 180 + 200}ms`}><span class="term-prompt">andy@studio</span><span class="term-sep">:</span><span class="term-cwd">~</span><span class="term-sep">$</span><span class="term-cmd">{line}</span></span>{#if i < installLines.length - 1}{"\n"}{/if}{/each}
<span class="term-row term-row-ok" style={`animation-delay:${installLines.length * 180 + 240}ms`}><span class="term-ok">✓</span><span class="term-out">Codex Pet Bar installed. Look up.</span></span></code></pre>
    </div>

    <ul class="install-fine">
      <li><span>1.</span>The installer drops hooks under <code>~/.codex/hooks/</code> — non-destructive.</li>
      <li><span>2.</span>The app lives in your <strong>Applications</strong> folder. Quit anytime to disable.</li>
      <li><span>3.</span>Need uninstall? <code>./script/uninstall.sh</code>. Pets clean up after themselves.</li>
    </ul>
  </section>

  <!-- ░░ MOMENTS ░░ -->
  <section class="moments" id="moments">
    <header class="section-head">
      <span class="section-eyebrow">HOW IT REACTS</span>
      <h2 class="section-title">A different pet for <em>every</em> kind of moment.</h2>
      <p class="section-lede">
        Codex Pet Bar listens to lifecycle hooks and turns them into a small, readable
        state change — instead of another notification.
      </p>
    </header>

    <div class="moment-rail" aria-hidden="true"></div>

    {#each moments as m, i}
      <article class={`moment moment-${m.tone}`} class:reverse={i === 1}>
        <div class="moment-art-frame">
          <div class="moment-art-glow" aria-hidden="true"></div>
          <img src={m.img} alt={m.pet} class="moment-art-img" />
          <span class="moment-badge">{m.pet}</span>
        </div>

        <div class="moment-copy">
          <div class="moment-meta">
            <span class="moment-num">{m.no}</span>
            <span class="moment-eyebrow">{m.eyebrow}</span>
          </div>
          <h3 class="moment-h">{m.title}</h3>
          <p class="moment-body">{m.body}</p>
          <p class="moment-hook">
            <span class="hook-label">hook</span>
            <code>{m.hook}</code>
          </p>
        </div>
      </article>
    {/each}
  </section>

  <!-- ░░ WHY ░░ -->
  <section class="why" id="why">
    <header class="section-head">
      <span class="section-eyebrow">PRINCIPLES</span>
      <h2 class="section-title">Built for the corner of your <em>eye</em>.</h2>
      <p class="section-lede">
        A few rules the project tries to keep, because they're the reason you'd use a tool
        like this in the first place.
      </p>
    </header>

    <ul class="feature-grid">
      {#each features as f, i}
        <li class="feature" style={`--i:${i}`}>
          <span class="feature-glyph" aria-hidden="true">{f.glyph}</span>
          <h3>{f.h}</h3>
          <p>{f.t}</p>
        </li>
      {/each}
    </ul>
  </section>

  <!-- ░░ FINAL CTA ░░ -->
  <section class="final-cta">
    <div class="cta-card">
      <img src="/artwork/codex-pet-bar-icon.png" alt="" class="cta-icon" />
      <div class="cta-copy">
        <h2>Ready to adopt the pack?</h2>
        <p>Three lines and the pets move in. They settle quickly.</p>
      </div>
      <div class="cta-actions">
        <a class="btn btn-primary" href="#install">
          <span class="btn-arrow">↓</span>
          Install
        </a>
        <a class="btn btn-ghost-light" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
          Read the source ↗
        </a>
      </div>
    </div>
  </section>

  <!-- ░░ FOOTER ░░ -->
  <footer class="footer">
    <div class="footer-peek" aria-hidden="true">
      <img src="/artwork/moments/approval-rock.png" alt="" class="peek peek-1" />
      <img src="/artwork/moments/running-flame.png" alt="" class="peek peek-2" />
      <img src="/artwork/moments/completed-ajt.png" alt="" class="peek peek-3" />
    </div>
    <div class="footer-grid">
      <div>
        <p class="ft-brand">Codex Pet Bar</p>
        <p class="ft-desc">
          A macOS menu-bar companion for Codex. Tiny pets that listen to local activity
          and react in real time. Open source, MIT.
        </p>
      </div>
      <div>
        <p class="ft-h">Project</p>
        <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">GitHub</a>
        <a href="https://github.com/andytyler/codex-pet-bar/issues" target="_blank" rel="noreferrer">Issues</a>
        <a href="https://github.com/andytyler/codex-pet-bar/blob/main/LICENSE" target="_blank" rel="noreferrer">MIT licence</a>
      </div>
      <div>
        <p class="ft-h">Author</p>
        <a href="https://ajt.dev" target="_blank" rel="noreferrer">ajt.dev</a>
        <a href="/">Other landings</a>
      </div>
      <div>
        <p class="ft-h">Compare</p>
        <a href="/">/</a>
        <a href="/claude">/claude</a>
        <a href="/new">/new</a>
        <a href="/reimagine">/reimagine</a>
      </div>
    </div>
    <p class="ft-end">
      Made with <span class="codex-mark">▸_</span> Codex by
      <a href="https://ajt.dev" target="_blank" rel="noreferrer">Andy&nbsp;Tyler</a>
      in 🇬🇧 · © MMXXVI
    </p>
  </footer>
</div>

<style>
  /* ================================================================
     ORIGINAL — a refined take on the canonical landing
     ================================================================ */
  .root {
    --paper:        #f8fbff;
    --paper-2:      #eef4ff;
    --surface:      #ffffff;
    --ink:          #0a1530;
    --ink-soft:     #3c4a6e;
    --ink-faint:    #7a85a3;
    --line:         #dbe3f1;
    --line-strong:  #b9c5db;

    --cobalt:       #1d5fff;
    --cobalt-deep:  #0a3bd1;
    --sky:          #4a8dff;
    --sky-soft:     #cfe0ff;
    --amber:        #ffb04a;
    --green:        #2da14a;
    --coral:        #ff6b4a;

    --font-display: "Inter Tight", system-ui, sans-serif;
    --font-body:    "Inter Tight", system-ui, sans-serif;
    --font-serif:   "Instrument Serif", "Times New Roman", serif;
    --font-mono:    "JetBrains Mono", ui-monospace, monospace;

    position: relative;
    min-height: 100vh;
    color: var(--ink);
    font-family: var(--font-body);
    font-feature-settings: "ss01", "ss02", "cv11";
    -webkit-font-smoothing: antialiased;
    line-height: 1.55;
    background: var(--paper);
    overflow-x: hidden;
  }
  :global(body:has(.root)) { background: var(--paper) !important; margin: 0; }
  ::selection { background: var(--cobalt); color: white; }

  /* ░░ ATMOSPHERE ░░ */
  .atmosphere {
    position: fixed;
    inset: 0;
    pointer-events: none;
    z-index: 0;
  }
  .halo {
    position: absolute;
    border-radius: 50%;
    filter: blur(120px);
    opacity: 0.55;
  }
  .halo-1 {
    top: -10%; right: -10%;
    width: 60%; height: 60%;
    background: radial-gradient(circle, var(--sky-soft), transparent 60%);
  }
  .halo-2 {
    top: 20%; left: -15%;
    width: 50%; height: 60%;
    background: radial-gradient(circle, #ffe6c8, transparent 60%);
    opacity: 0.45;
  }
  .grain {
    position: absolute; inset: 0;
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' seed='6'/><feColorMatrix values='0 0 0 0 0.04  0 0 0 0 0.08  0 0 0 0 0.18  0 0 0 0.5 0'/></filter><rect width='100%' height='100%' filter='url(%23n)' opacity='0.18'/></svg>");
    opacity: 0.6;
    mix-blend-mode: multiply;
  }
  .root > *:not(.atmosphere) { position: relative; z-index: 1; }

  /* ░░ NAV ░░ */
  .nav {
    position: fixed;
    top: 14px; left: 0; right: 0;
    z-index: 40;
    padding: 0 clamp(12px, 3vw, 28px);
    transition: top 280ms ease;
  }
  .nav.scrolled { top: 10px; }
  .nav-inner {
    max-width: 1200px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    gap: 14px;
    padding: 8px 12px 8px 16px;
    background: rgba(255, 255, 255, 0.72);
    backdrop-filter: blur(16px) saturate(1.4);
    -webkit-backdrop-filter: blur(16px) saturate(1.4);
    border: 1px solid rgba(10, 21, 48, 0.08);
    border-radius: 999px;
    box-shadow:
      0 2px 1px rgba(255, 255, 255, 0.5) inset,
      0 12px 32px -16px rgba(10, 21, 48, 0.18);
    transition: max-width 320ms ease;
  }
  .brand {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    text-decoration: none;
    color: var(--ink);
    font-size: 14.5px;
    font-weight: 600;
    letter-spacing: -0.01em;
  }
  .brand img {
    width: 28px; height: 28px;
    border-radius: 7px;
    box-shadow: 0 2px 4px rgba(10, 21, 48, 0.15);
  }
  .nav-links {
    list-style: none; padding: 0; margin: 0;
    display: flex; align-items: center; gap: 24px;
  }
  .nav-links a {
    color: var(--ink-soft);
    text-decoration: none;
    font-size: 14px;
    font-weight: 500;
    transition: color 120ms ease;
  }
  .nav-links a:hover { color: var(--cobalt); }
  .nav-actions { justify-self: end; }
  .nav-gh {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 14px;
    background: var(--ink);
    color: white;
    border-radius: 999px;
    font-size: 13.5px;
    font-weight: 600;
    text-decoration: none;
    transition: background 160ms ease, transform 160ms ease;
  }
  .nav-gh:hover { background: var(--cobalt); transform: translateY(-1px); }
  .gh-star { color: var(--amber); }
  @media (max-width: 720px) {
    .nav-links { display: none; }
    .nav-inner { grid-template-columns: 1fr auto; }
  }

  /* ░░ HERO ░░ */
  .hero {
    max-width: 1200px;
    margin: 0 auto;
    padding: 120px clamp(20px, 4vw, 48px) 30px;
    text-align: center;
  }

  /* live menubar */
  .livedemo {
    max-width: 580px;
    margin: 0 auto 36px;
  }
  .livedemo-bar {
    --tone: var(--sky);
    height: 36px;
    background: rgba(10, 21, 48, 0.92);
    color: white;
    border-radius: 10px;
    border: 1px solid rgba(255, 255, 255, 0.08);
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.08) inset,
      0 18px 40px -10px rgba(10, 21, 48, 0.35);
    padding: 0 12px;
    display: flex;
    align-items: center;
    gap: 10px;
    font-family: var(--font-mono);
    font-size: 12px;
    overflow: hidden;
  }
  .livedemo-bar.tone-blue   { --tone: #5a9eff; }
  .livedemo-bar.tone-amber  { --tone: #ffb04a; }
  .livedemo-bar.tone-green  { --tone: #4eda7a; }
  .ld-apple { width: 9px; height: 9px; border-radius: 50%; background: white; flex-shrink: 0; opacity: 0.9; }
  .ld-app { font-weight: 600; opacity: 0.85; }
  .ld-spacer { flex: 1; }
  .ld-status { display: inline-flex; align-items: center; gap: 6px; color: var(--tone); transition: color 320ms ease; min-width: 130px; justify-content: flex-end; }
  .ld-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--tone); box-shadow: 0 0 0 2px rgba(255,255,255,0.06), 0 0 10px var(--tone); animation: ldpulse 1.8s ease-in-out infinite; }
  @keyframes ldpulse { 0%,100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.4); opacity: 0.65; } }
  .ld-label { letter-spacing: 0.03em; font-weight: 500; }
  .ld-petwrap { position: relative; width: 28px; height: 28px; flex-shrink: 0; }
  .ld-pet {
    position: absolute; inset: 0;
    width: 100%; height: 100%;
    object-fit: contain;
    opacity: 0;
    transform: translateY(8px) scale(0.85);
    transition: opacity 280ms ease, transform 380ms cubic-bezier(.16,.84,.32,1);
    filter: drop-shadow(0 2px 4px rgba(0,0,0,0.4));
  }
  .ld-pet.active { opacity: 1; transform: translateY(-1px) scale(1); }
  .ld-meta { color: rgba(255,255,255,0.35); letter-spacing: 0.12em; }
  .ld-clock { font-weight: 600; min-width: 60px; text-align: right; opacity: 0.85; }
  .livedemo-cap {
    text-align: center;
    margin: 10px 0 0;
    font-family: var(--font-serif);
    font-style: italic;
    font-size: 14px;
    color: var(--ink-soft);
  }

  /* hero copy */
  .kicker {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 6px 14px;
    background: white;
    border: 1px solid var(--line);
    border-radius: 999px;
    font-size: 13px;
    color: var(--ink-soft);
    margin-bottom: 28px;
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.5) inset, 0 4px 10px -4px rgba(10, 21, 48, 0.08);
  }
  .kicker em { color: var(--cobalt); font-style: normal; font-weight: 600; }
  .kicker-dot {
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--cobalt);
    box-shadow: 0 0 0 3px rgba(29, 95, 255, 0.15);
  }

  .hero-title {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(48px, 7.4vw, 104px);
    line-height: 0.96;
    letter-spacing: -0.035em;
    margin: 0 0 26px;
    font-variation-settings: "opsz" 32, "wght" 700;
  }
  .hero-title .line { display: block; }
  .hero-title em {
    font-family: var(--font-serif);
    font-style: italic;
    font-weight: 400;
    color: var(--cobalt);
    letter-spacing: -0.02em;
    padding: 0 0.04em;
  }
  .mounted .hero-title .line { opacity: 0; transform: translateY(20px); animation: rise 820ms cubic-bezier(.16,.84,.32,1) forwards; }
  .mounted .line-1 { animation-delay: 80ms; }
  .mounted .line-2 { animation-delay: 200ms; }
  .mounted .line-3 { animation-delay: 320ms; }
  @keyframes rise { to { opacity: 1; transform: translateY(0); } }

  .hero-lede {
    max-width: 56ch;
    margin: 0 auto 32px;
    font-size: clamp(15.5px, 1.3vw, 18px);
    line-height: 1.55;
    color: var(--ink-soft);
  }
  .hero-lede em { color: var(--ink); font-style: italic; font-family: var(--font-serif); }

  .hero-actions {
    display: flex; justify-content: center;
    gap: 12px; flex-wrap: wrap;
    margin-bottom: 28px;
  }
  .btn {
    appearance: none; border: 0;
    cursor: pointer;
    text-decoration: none;
    font-family: var(--font-body);
    font-weight: 600;
    font-size: 15px;
    letter-spacing: -0.005em;
    padding: 13px 22px;
    border-radius: 999px;
    display: inline-flex; align-items: center; gap: 9px;
    transition: transform 160ms cubic-bezier(.2,.7,.2,1), box-shadow 160ms ease, background 160ms ease;
  }
  .btn-primary {
    background: var(--cobalt);
    color: white;
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.2) inset,
      0 10px 24px -8px rgba(29, 95, 255, 0.55);
  }
  .btn-primary:hover {
    background: var(--cobalt-deep);
    transform: translateY(-2px);
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.2) inset,
      0 14px 32px -8px rgba(29, 95, 255, 0.6);
  }
  .btn-ghost {
    background: white;
    color: var(--ink);
    border: 1px solid var(--line);
    box-shadow: 0 4px 14px -8px rgba(10, 21, 48, 0.18);
  }
  .btn-ghost:hover { transform: translateY(-2px); border-color: var(--line-strong); }
  .btn-ghost-light {
    background: rgba(255,255,255,0.12);
    color: white;
    border: 1px solid rgba(255,255,255,0.25);
  }
  .btn-ghost-light:hover { background: rgba(255,255,255,0.2); transform: translateY(-2px); }
  .btn-arrow { font-size: 12px; }

  .hero-specs {
    list-style: none;
    padding: 0; margin: 0;
    display: inline-flex; flex-wrap: wrap; align-items: center; gap: 18px;
    font-size: 13.5px;
    color: var(--ink-faint);
  }
  .hero-specs li {
    display: inline-flex; align-items: center; gap: 8px;
    position: relative;
  }
  .hero-specs li + li::before {
    content: "·";
    position: absolute; left: -12px;
    opacity: 0.5;
  }
  .dot {
    display: inline-block;
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 0 3px rgba(45, 161, 74, 0.18);
    animation: dotPulse 2s ease-in-out infinite;
  }
  @keyframes dotPulse { 0%,100% { box-shadow: 0 0 0 3px rgba(45,161,74,0.18); } 50% { box-shadow: 0 0 0 6px rgba(45,161,74,0.06); } }

  /* HERO STAGE */
  .stage {
    position: relative;
    margin: 60px auto 0;
    max-width: 1080px;
    aspect-ratio: 16 / 9;
  }
  .stage-glow {
    position: absolute;
    inset: 0;
    background: radial-gradient(50% 60% at 50% 65%, rgba(29, 95, 255, 0.18) 0%, transparent 70%);
    pointer-events: none;
  }
  .stage-base {
    position: absolute;
    bottom: 0; left: 50%;
    transform: translateX(-50%);
    width: 80%; height: 30px;
    background: radial-gradient(50% 100% at 50% 50%, rgba(10, 21, 48, 0.18), transparent 70%);
    filter: blur(4px);
    pointer-events: none;
  }
  .stage-img {
    position: relative;
    width: 100%; height: 100%;
    object-fit: contain;
    filter: drop-shadow(0 24px 32px rgba(10, 21, 48, 0.25));
    animation: floaty 6.5s ease-in-out infinite;
  }
  @keyframes floaty {
    0%, 100% { transform: translateY(0); }
    50%      { transform: translateY(-10px); }
  }
  .stage-pin {
    position: absolute;
    background: white;
    border: 1px solid var(--line);
    border-radius: 999px;
    padding: 6px 12px;
    font-family: var(--font-mono);
    font-size: 11px;
    letter-spacing: 0.08em;
    color: var(--ink);
    box-shadow: 0 6px 14px -6px rgba(10, 21, 48, 0.2);
    white-space: nowrap;
  }
  .pin-a { top: 12%; right: 4%; transform: rotate(4deg); color: var(--cobalt); }
  .pin-b { bottom: 22%; left: 0%; transform: rotate(-3deg); color: var(--amber); }
  @media (max-width: 720px) {
    .stage-pin { display: none; }
    .stage { margin-top: 30px; }
  }

  /* ░░ SECTION HEAD ░░ */
  .section-head {
    max-width: 760px;
    margin: 0 auto 60px;
    padding: 0 clamp(20px, 4vw, 48px);
    text-align: center;
  }
  .section-eyebrow {
    display: inline-block;
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--cobalt);
    letter-spacing: 0.18em;
    margin-bottom: 14px;
    padding: 4px 10px;
    border: 1px solid var(--sky-soft);
    border-radius: 999px;
    background: rgba(207, 224, 255, 0.4);
  }
  .section-title {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(34px, 4.4vw, 60px);
    line-height: 1.02;
    letter-spacing: -0.03em;
    margin: 0 0 16px;
    font-variation-settings: "opsz" 32, "wght" 700;
  }
  .section-title em {
    font-family: var(--font-serif);
    font-style: italic;
    font-weight: 400;
    color: var(--cobalt);
    padding: 0 0.04em;
  }
  .section-lede {
    font-size: 17px;
    line-height: 1.55;
    color: var(--ink-soft);
    margin: 0;
  }
  .inline-code {
    font-family: var(--font-mono);
    font-size: 0.9em;
    padding: 2px 8px;
    background: var(--paper-2);
    border: 1px solid var(--line);
    border-radius: 6px;
  }

  /* ░░ INSTALL ░░ */
  .install {
    max-width: 980px;
    margin: 100px auto;
    padding: 0 clamp(20px, 4vw, 48px);
  }
  .term-frame {
    background: #0a1530;
    border-radius: 18px;
    overflow: hidden;
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.08) inset,
      0 30px 60px -20px rgba(10, 21, 48, 0.5);
    border: 1px solid rgba(10, 21, 48, 0.6);
  }
  .term-head {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: 14px;
    padding: 11px 14px;
    background: #0e1a3c;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  }
  .term-lights { display: inline-flex; gap: 6px; }
  .tl { width: 12px; height: 12px; border-radius: 50%; box-shadow: 0 0 0 0.5px rgba(0,0,0,0.4) inset; }
  .tl-r { background: #ff5f57; }
  .tl-y { background: #febc2e; }
  .tl-g { background: #28c840; }
  .term-title {
    font-family: var(--font-mono);
    font-size: 12px;
    color: rgba(255,255,255,0.55);
    text-align: center;
  }
  .term-copy {
    appearance: none;
    background: rgba(255,255,255,0.08);
    color: white;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 999px;
    padding: 5px 13px;
    font-family: var(--font-mono);
    font-size: 11.5px;
    cursor: pointer;
    transition: background 120ms ease;
  }
  .term-copy:hover { background: rgba(255,255,255,0.16); }
  .term-body {
    margin: 0;
    padding: 22px 26px;
    font-family: var(--font-mono);
    font-size: 14px;
    line-height: 1.85;
    color: #d8e3f5;
    background: linear-gradient(180deg, rgba(255,255,255,0.02), transparent);
    overflow-x: auto;
  }
  .term-row {
    display: block;
    opacity: 0;
    transform: translateY(2px);
    animation: termRow 320ms ease-out forwards;
  }
  @keyframes termRow { to { opacity: 1; transform: translateY(0); } }
  .term-prompt { color: #ffb04a; }
  .term-sep    { color: rgba(255,255,255,0.35); margin: 0 2px; }
  .term-cwd    { color: #5a9eff; }
  .term-cmd    { color: white; margin-left: 8px; }
  .term-row-ok { padding-top: 10px; }
  .term-ok     { color: #4eda7a; margin-right: 10px; }
  .term-out    { color: rgba(255,255,255,0.8); }

  .install-fine {
    list-style: none;
    padding: 22px 0 0; margin: 0;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px;
    font-size: 13.5px;
    color: var(--ink-soft);
  }
  @media (max-width: 760px) { .install-fine { grid-template-columns: 1fr; } }
  .install-fine li {
    display: grid;
    grid-template-columns: 24px 1fr;
    gap: 6px;
    align-items: baseline;
  }
  .install-fine li span {
    font-family: var(--font-mono);
    color: var(--cobalt);
    font-weight: 600;
  }
  .install-fine code {
    font-family: var(--font-mono);
    font-size: 12px;
    background: var(--paper-2);
    border: 1px solid var(--line);
    padding: 1px 6px;
    border-radius: 5px;
  }

  /* ░░ MOMENTS ░░ */
  .moments {
    max-width: 1140px;
    margin: 120px auto;
    padding: 0 clamp(20px, 4vw, 48px);
    position: relative;
  }
  .moment-rail {
    position: absolute;
    left: 50%; top: 280px; bottom: 60px;
    width: 1px;
    background-image: linear-gradient(to bottom, var(--line-strong) 50%, transparent 50%);
    background-size: 1px 12px;
    transform: translateX(-50%);
    pointer-events: none;
  }
  @media (max-width: 920px) { .moment-rail { display: none; } }

  .moment {
    position: relative;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 24px;
    padding: clamp(24px, 3.5vw, 44px);
    margin: 28px 0;
    display: grid;
    grid-template-columns: 0.85fr 1fr;
    gap: clamp(20px, 4vw, 48px);
    align-items: center;
    box-shadow: 0 20px 40px -22px rgba(10, 21, 48, 0.18);
    transition: transform 260ms ease, box-shadow 260ms ease;
  }
  .moment:hover {
    transform: translateY(-3px);
    box-shadow: 0 28px 50px -20px rgba(10, 21, 48, 0.25);
  }
  .moment.reverse { grid-template-columns: 1fr 0.85fr; }
  .moment.reverse .moment-art-frame { order: 2; }
  @media (max-width: 860px) {
    .moment, .moment.reverse { grid-template-columns: 1fr; }
    .moment.reverse .moment-art-frame { order: 0; }
  }

  .moment-art-frame {
    position: relative;
    aspect-ratio: 1 / 1;
    background:
      radial-gradient(circle at 50% 60%, var(--paper-2) 0%, var(--surface) 70%);
    border: 1px solid var(--line);
    border-radius: 20px;
    display: grid; place-items: center;
    padding: 18px;
    overflow: hidden;
  }
  .moment-art-glow {
    position: absolute; inset: 0;
    background: radial-gradient(circle at 50% 60%, currentColor 0%, transparent 50%);
    opacity: 0.18;
    pointer-events: none;
  }
  .moment-blue  .moment-art-glow { color: var(--cobalt); }
  .moment-amber .moment-art-glow { color: var(--amber); }
  .moment-green .moment-art-glow { color: var(--green); }

  .moment-art-img {
    position: relative;
    width: 78%;
    max-height: 86%;
    object-fit: contain;
    filter: drop-shadow(0 16px 18px rgba(10, 21, 48, 0.2));
    animation: bobMid 5s ease-in-out infinite;
  }
  @keyframes bobMid {
    0%,100% { transform: translateY(0) rotate(-1deg); }
    50%     { transform: translateY(-8px) rotate(1deg); }
  }
  .moment-badge {
    position: absolute;
    bottom: 14px; left: 14px;
    background: var(--ink);
    color: white;
    font-family: var(--font-mono);
    font-size: 11px;
    padding: 4px 10px;
    border-radius: 999px;
    letter-spacing: 0.08em;
  }

  .moment-meta { display: flex; align-items: center; gap: 12px; margin-bottom: 14px; }
  .moment-num {
    font-family: var(--font-mono);
    font-size: 12px;
    color: white;
    background: var(--cobalt);
    padding: 3px 10px;
    border-radius: 999px;
    letter-spacing: 0.04em;
    font-weight: 600;
  }
  .moment-amber .moment-num { background: var(--amber); color: var(--ink); }
  .moment-green .moment-num { background: var(--green); }
  .moment-eyebrow {
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--ink-faint);
    letter-spacing: 0.16em;
  }
  .moment-h {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(26px, 3.2vw, 40px);
    line-height: 1.05;
    letter-spacing: -0.025em;
    margin: 0 0 14px;
    font-variation-settings: "opsz" 28, "wght" 700;
  }
  .moment-body {
    margin: 0 0 18px;
    font-size: 16.5px;
    line-height: 1.55;
    color: var(--ink-soft);
    max-width: 50ch;
  }
  .moment-hook {
    margin: 0;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 6px 10px 6px 6px;
    background: var(--paper-2);
    border: 1px solid var(--line);
    border-radius: 10px;
  }
  .hook-label {
    font-family: var(--font-mono);
    font-size: 10.5px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.12em;
    background: white;
    border: 1px solid var(--line);
    padding: 2px 6px;
    border-radius: 5px;
  }
  .moment-hook code {
    font-family: var(--font-mono);
    font-size: 12.5px;
    color: var(--ink);
  }

  /* ░░ FEATURES ░░ */
  .why {
    max-width: 1140px;
    margin: 120px auto;
    padding: 0 clamp(20px, 4vw, 48px);
  }
  .feature-grid {
    list-style: none;
    padding: 0; margin: 0;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
  }
  @media (max-width: 920px) { .feature-grid { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 520px) { .feature-grid { grid-template-columns: 1fr; } }
  .feature {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 18px;
    padding: 22px 22px 24px;
    transition: transform 220ms ease, border-color 220ms ease, box-shadow 220ms ease;
    position: relative;
    overflow: hidden;
  }
  .feature::before {
    content: ""; position: absolute;
    inset: -1px;
    border-radius: inherit;
    padding: 1px;
    background: linear-gradient(135deg, transparent 30%, rgba(29, 95, 255, 0.3) 100%);
    -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
            mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
            mask-composite: exclude;
    opacity: 0;
    transition: opacity 220ms ease;
    pointer-events: none;
  }
  .feature:hover { transform: translateY(-3px); border-color: var(--line-strong); box-shadow: 0 20px 38px -22px rgba(10, 21, 48, 0.2); }
  .feature:hover::before { opacity: 1; }
  .feature-glyph {
    display: inline-flex;
    align-items: center; justify-content: center;
    width: 36px; height: 36px;
    border-radius: 10px;
    background: var(--paper-2);
    border: 1px solid var(--line);
    color: var(--cobalt);
    font-size: 18px;
    margin-bottom: 14px;
  }
  .feature h3 {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 17px;
    margin: 0 0 6px;
    letter-spacing: -0.01em;
  }
  .feature p {
    margin: 0;
    font-size: 14px;
    line-height: 1.55;
    color: var(--ink-soft);
  }

  /* ░░ FINAL CTA ░░ */
  .final-cta {
    max-width: 1140px;
    margin: 120px auto 80px;
    padding: 0 clamp(20px, 4vw, 48px);
  }
  .cta-card {
    background:
      radial-gradient(circle at 20% 0%, rgba(74, 141, 255, 0.4) 0%, transparent 50%),
      linear-gradient(135deg, var(--cobalt) 0%, var(--cobalt-deep) 100%);
    color: white;
    border-radius: 26px;
    padding: clamp(28px, 4vw, 48px);
    display: grid;
    grid-template-columns: auto 1fr auto;
    gap: clamp(20px, 3vw, 36px);
    align-items: center;
    box-shadow:
      0 1px 0 rgba(255, 255, 255, 0.2) inset,
      0 30px 60px -24px rgba(29, 95, 255, 0.5);
    position: relative;
    overflow: hidden;
  }
  .cta-card::before {
    content: ""; position: absolute;
    right: -80px; bottom: -120px;
    width: 320px; height: 320px;
    background: radial-gradient(circle, rgba(255,255,255,0.2), transparent 60%);
    filter: blur(40px);
    pointer-events: none;
  }
  @media (max-width: 760px) {
    .cta-card { grid-template-columns: auto 1fr; }
    .cta-actions { grid-column: 1 / -1; justify-self: stretch; display: flex; flex-wrap: wrap; gap: 12px; }
  }
  .cta-icon {
    width: 72px; height: 72px;
    border-radius: 16px;
    box-shadow: 0 8px 16px rgba(10, 21, 48, 0.4);
  }
  .cta-copy h2 {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(24px, 2.6vw, 34px);
    margin: 0 0 4px;
    letter-spacing: -0.02em;
  }
  .cta-copy p {
    margin: 0;
    color: rgba(255, 255, 255, 0.8);
    font-size: 15.5px;
  }
  .cta-actions { display: flex; gap: 10px; flex-wrap: wrap; }
  .cta-actions .btn-primary {
    background: white;
    color: var(--cobalt);
    box-shadow: 0 8px 20px -8px rgba(0,0,0,0.3);
  }
  .cta-actions .btn-primary:hover { background: var(--paper-2); }

  /* ░░ FOOTER ░░ */
  .footer {
    position: relative;
    background: var(--ink);
    color: rgba(255, 255, 255, 0.85);
    padding: 90px clamp(20px, 4vw, 48px) 36px;
    overflow: hidden;
  }
  .footer-peek {
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 100px;
    pointer-events: none;
  }
  .peek {
    position: absolute;
    width: 100px; height: 100px;
    object-fit: contain;
    transform: translateY(-55%);
    filter: drop-shadow(0 8px 14px rgba(0,0,0,0.45));
    animation: peekBob 5s ease-in-out infinite;
  }
  .peek-1 { left: 10%; }
  .peek-2 { left: 50%; transform: translate(-50%, -55%); animation-delay: 1s; }
  .peek-3 { right: 10%; animation-delay: 2s; }
  @keyframes peekBob {
    0%, 100% { transform: translateY(-55%) rotate(-2deg); }
    50%      { transform: translateY(-62%) rotate(2deg); }
  }
  .peek-2 {
    animation-name: peekBobCenter;
  }
  @keyframes peekBobCenter {
    0%, 100% { transform: translate(-50%, -55%) rotate(-2deg); }
    50%      { transform: translate(-50%, -62%) rotate(2deg); }
  }
  @media (max-width: 720px) { .peek-1, .peek-3 { display: none; } .peek-2 { width: 72px; height: 72px; } }

  .footer-grid {
    max-width: 1140px;
    margin: 40px auto 0;
    display: grid;
    grid-template-columns: 2fr 1fr 1fr 1fr;
    gap: 40px;
    position: relative;
  }
  @media (max-width: 760px) { .footer-grid { grid-template-columns: 1fr 1fr; } }
  @media (max-width: 480px) { .footer-grid { grid-template-columns: 1fr; } }

  .ft-brand {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 22px;
    margin: 0 0 8px;
    color: white;
    letter-spacing: -0.02em;
  }
  .ft-desc { margin: 0; max-width: 38ch; color: rgba(255,255,255,0.65); font-size: 14.5px; line-height: 1.55; }
  .ft-h {
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: rgba(255,255,255,0.45);
    letter-spacing: 0.16em;
    margin: 0 0 12px;
    text-transform: uppercase;
  }
  .footer-grid div a {
    display: block;
    color: rgba(255,255,255,0.85);
    text-decoration: none;
    padding: 5px 0;
    font-size: 14.5px;
    transition: color 120ms ease, transform 120ms ease;
  }
  .footer-grid div a:hover { color: white; transform: translateX(2px); }
  .ft-end {
    max-width: 1140px;
    margin: 60px auto 0;
    padding-top: 24px;
    border-top: 1px solid rgba(255, 255, 255, 0.1);
    text-align: center;
    color: rgba(255,255,255,0.45);
    font-size: 13px;
  }
  .ft-end a { color: white; text-decoration: none; border-bottom: 1px dotted rgba(255,255,255,0.4); }
  .ft-end a:hover { color: var(--amber); }
  .codex-mark {
    font-family: var(--font-mono);
    background: rgba(255,255,255,0.08);
    border: 1px solid rgba(255,255,255,0.18);
    padding: 1px 7px;
    border-radius: 5px;
    font-size: 12px;
  }

  @media (prefers-reduced-motion: reduce) {
    .stage-img, .moment-art-img, .peek, .dot, .kicker-dot, .ld-dot, .ld-pet,
    .hero-title .line, .term-row { animation: none !important; transform: none !important; }
    .mounted .hero-title .line, .term-row { opacity: 1 !important; }
    .ld-pet.active { opacity: 1; }
  }
</style>

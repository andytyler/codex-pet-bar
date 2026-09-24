<script lang="ts">
  import { onMount } from "svelte";

  const installCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";
  const installLines = installCommand.split("\n");

  let copied = $state(false);
  let resetTimer: ReturnType<typeof setTimeout> | undefined;
  let mx = $state(0);
  let my = $state(0);
  let mounted = $state(false);

  // -- Mini live menubar demo state --
  type LiveState = { label: string; img: string; tone: string };
  const liveStates: LiveState[] = [
    { label: "listening",        img: "/artwork/moments/approval-rock.png",  tone: "blue" },
    { label: "running tools",    img: "/artwork/moments/running-flame.png",  tone: "orange" },
    { label: "thread complete",  img: "/artwork/moments/completed-ajt.png",  tone: "green" },
  ];
  let liveIdx = $state(0);
  let liveTime = $state("--:--");

  // -- Per-card 3D tilt + shimmer state --
  type Tilt = { rx: number; ry: number; sx: number; sy: number; on: boolean };
  let tilts: Tilt[] = $state([
    { rx: 0, ry: 0, sx: 50, sy: 50, on: false },
    { rx: 0, ry: 0, sx: 50, sy: 50, on: false },
    { rx: 0, ry: 0, sx: 50, sy: 50, on: false },
  ]);

  const onCardMove = (e: PointerEvent, i: number) => {
    const el = e.currentTarget as HTMLElement;
    const r = el.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width;
    const py = (e.clientY - r.top) / r.height;
    tilts[i] = {
      rx: (py - 0.5) * -10,
      ry: (px - 0.5) * 12,
      sx: px * 100,
      sy: py * 100,
      on: true,
    };
  };
  const onCardLeave = (i: number) => {
    tilts[i] = { rx: 0, ry: 0, sx: 50, sy: 50, on: false };
  };

  // -- Scroll-driven buddy lean --
  let scrollY = $state(0);
  let lastScroll = 0;
  let buddyLean = $state(0);

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
    liveTime = `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")}`;
  };

  onMount(() => {
    mounted = true;
    tickClock();
    const cl = setInterval(tickClock, 30_000);
    const li = setInterval(() => {
      liveIdx = (liveIdx + 1) % liveStates.length;
    }, 2600);

    const onMove = (e: PointerEvent) => {
      mx = (e.clientX / window.innerWidth - 0.5) * 2;
      my = (e.clientY / window.innerHeight - 0.5) * 2;
    };
    const onScroll = () => {
      scrollY = window.scrollY;
      const dy = scrollY - lastScroll;
      buddyLean = Math.max(-14, Math.min(14, dy * 1.4));
      lastScroll = scrollY;
      // gently ease back to 0
      requestAnimationFrame(() => (buddyLean *= 0.6));
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("scroll", onScroll);
      clearInterval(cl);
      clearInterval(li);
      clearTimeout(resetTimer);
    };
  });

  const cards = [
    {
      no: "№ 001",
      edition: "1st EDITION",
      name: "Rock",
      latin: "Petrosus statusbarensis",
      type: "Sentry",
      img: "/artwork/moments/approval-rock.png",
      bg: "rock",
      flag: "Permission",
      hook: "PermissionRequest",
      flavor: "Holds the flag the moment Codex pauses for consent. Will wait forever.",
      tags: ["Mineral", "Patient", "Steady"],
      stats: [["Patience", 99], ["Speed", 12], ["Cuteness", 88]] as [string, number][],
    },
    {
      no: "№ 002",
      edition: "1st EDITION",
      name: "Flame",
      latin: "Ignis cursoria",
      type: "Runner",
      img: "/artwork/moments/running-flame.png",
      bg: "flame",
      flag: "Tool-Use",
      hook: "PreToolUse",
      flavor: "Trots steadily while Codex edits, searches, or shells out. Never tires.",
      tags: ["Fire", "Cape", "Restless"],
      stats: [["Stamina", 92], ["Vibes", 86], ["Heat", 100]] as [string, number][],
    },
    {
      no: "№ 003",
      edition: "1st EDITION",
      name: "AJT",
      latin: "Festivus completionis",
      type: "Finisher",
      img: "/artwork/moments/completed-ajt.png",
      bg: "ajt",
      flag: "Stop",
      hook: "PostToolUse",
      flavor: "Waves the checkered flag when your thread crosses the line. Beloved.",
      tags: ["Human", "Joyful", "Closer"],
      stats: [["Joy", 95], ["Closure", 90], ["Hair Volume", 100]] as [string, number][],
    },
  ];

  const benefits = [
    { emoji: "🏠", h: "Strictly local",        t: "Hooks read your local Codex activity and write small status updates beneath ~/.codex. Nothing leaves your laptop." },
    { emoji: "☁️", h: "No background cloud",   t: "It's a menu-bar utility, not a hosted service. No account, no telemetry, no server." },
    { emoji: "🛠", h: "Hackable pets",         t: "Pets are filesystem packages. Inspect them, fork them, or commission your own." },
    { emoji: "📜", h: "Open source, MIT",      t: "Made by Andy Tyler for people who like to hack on their tooling." },
  ];

  const marquee = [
    "ROCK · SENTRY", "FLAME · RUNNER", "AJT · FINISHER", "EAR · LISTENER",
    "GOBLIN · GREETER", "HALT · REVIEWER", "BLOB · WAITING", "GHOST · IDLE",
  ];

  const moments = [
    {
      no: "01", time: "14:22 — pause", title: "“This one needs you.”", tone: "rock",
      img: "/artwork/moments/approval-rock.png",
      body: "Codex hits a permission request. Rock pops up holding the Codex flag — a small stillness in the menu bar that says, your call. It waits, perfectly, until you approve or reject.",
      hook: "PermissionRequest → permission_requested",
    },
    {
      no: "02", time: "14:23 — running", title: "“I've got this part.”", tone: "flame",
      img: "/artwork/moments/running-flame.png",
      body: "You said yes. Flame is now jogging across the bar while Codex edits files, shells out, runs tests. The longer it goes, the more deliberate the gait.",
      hook: "PreToolUse → tool_started",
    },
    {
      no: "03", time: "14:31 — done", title: "“We did it.”", tone: "ajt",
      img: "/artwork/moments/completed-ajt.png",
      body: "The thread completes. AJT throws the checkered flag and the bar settles back to ambient. A tiny moment of closure that a notification couldn't deliver.",
      hook: "PostToolUse → stopped",
    },
  ];

  const live = $derived(liveStates[liveIdx]);
</script>

<svelte:head>
  <title>Codex Pet Bar — Your code editor could use a friend</title>
  <meta property="og:title" content="Codex Pet Bar — Your code editor could use a friend" />
  <meta property="og:description" content="Tiny 3D pets that live in your macOS menu bar and react to your Codex agent in real time." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-friend.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:alt" content="Codex Pet Bar social card with tiny 3D menu-bar pets and the line Your code editor could use a friend." />
  <meta name="twitter:image" content="/artwork/open-graph/codex-pet-bar-og-friend.png" />
  <meta name="twitter:image:alt" content="Codex Pet Bar social card with tiny 3D menu-bar pets and the line Your code editor could use a friend." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,200..800&family=Plus+Jakarta+Sans:ital,wght@0,200..800;1,200..800&family=JetBrains+Mono:wght@400..700&display=swap"
    rel="stylesheet" />
</svelte:head>

<div class="petworld" class:mounted style:--mx={mx} style:--my={my}>

  <!-- ═══════════════════ HERO ═══════════════════ -->
  <section class="hero">
    <!-- background sky -->
    <div class="sky" aria-hidden="true">
      <div class="sun"></div>
      <div class="cloud c1"></div>
      <div class="cloud c2"></div>
      <div class="cloud c3"></div>
    </div>

    <!-- top chrome -->
    <nav class="topbar">
      <a class="logo" href="#top">
        <img src="/artwork/codex-pet-bar-icon.png" alt="" />
        <span><strong>codex-pet-bar</strong>/<em>v0.1.2</em></span>
      </a>
      <ul class="topnav">
        <li><a href="#cast">The Cast</a></li>
        <li><a href="#day">A Day</a></li>
        <li><a href="#why">Why?</a></li>
        <li><a href="#adopt">Adopt</a></li>
        <li><a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer" class="topnav-gh">★ GitHub</a></li>
      </ul>
    </nav>

    <!-- LIVE MENUBAR DEMO -->
    <div class="livedemo" aria-label="A live preview of the menu bar pet">
      <div class={`livedemo-bar tone-${live.tone}`}>
        <span class="ld-apple"></span>
        <span class="ld-app">codex</span>
        <span class="ld-spacer"></span>
        <span class="ld-status">
          <span class="ld-dot"></span>
          <span class="ld-label">{live.label}</span>
        </span>
        <span class="ld-petwrap">
          {#each liveStates as s, i}
            <img src={s.img} alt="" class="ld-pet" class:active={i === liveIdx} />
          {/each}
        </span>
        <span class="ld-meta">●●○</span>
        <span class="ld-clock">{liveTime}</span>
      </div>
      <p class="livedemo-cap">↑ <span>your menu bar — but with a friend in it.</span></p>
    </div>

    <div class="hero-grid" id="top">
      <div class="hero-copy">
        <span class="kicker">A macOS menu-bar companion for Codex</span>
        <h1 class="hero-title">
          <span class="line">your code</span>
          <span class="line">editor could</span>
          <span class="line emph">use a friend.</span>
        </h1>
        <p class="hero-lede">
          Pop a tiny 3D creature into your menu bar. It listens to your local Codex agent
          and turns hooks, approvals, and tool runs into something you can <em>see</em> —
          not another notification.
        </p>

        <div class="hero-actions">
          <a class="btn btn-primary" href="#adopt">
            <span class="btn-arrow">▶</span> Adopt the pack
          </a>
          <a class="btn btn-ghost" href="#cast">Meet the cast →</a>
        </div>

        <div class="hero-meta">
          <span class="dot ok"></span>
          <span><strong>3 pets</strong> on duty · macOS 13+ · MIT licensed</span>
        </div>
      </div>

      <!-- floating ID cards -->
      <div class="floaters" aria-hidden="true">
        <div class="id-card f1">
          <img src="/artwork/moments/approval-rock.png" alt="" />
          <div>
            <p class="idc-h">ROCK</p>
            <p class="idc-s">on duty · {liveTime}</p>
          </div>
        </div>
        <div class="id-card f2">
          <img src="/artwork/moments/running-flame.png" alt="" />
          <div>
            <p class="idc-h">FLAME</p>
            <p class="idc-s">running tools…</p>
          </div>
        </div>
        <div class="id-card f3">
          <img src="/artwork/moments/completed-ajt.png" alt="" />
          <div>
            <p class="idc-h">AJT</p>
            <p class="idc-s">✓ thread done</p>
          </div>
        </div>
      </div>
    </div>

    <!-- full-bleed cast piled along the bottom edge -->
    <div class="hero-cast" aria-hidden="true">
      <img src="/artwork/codex-pet-bar-hero-trans.png" alt="A pile of menu-bar pets" />
    </div>

    <div class="scroll-cue" aria-hidden="true">
      <span>scroll</span>
      <span class="scroll-arrow">↓</span>
    </div>
  </section>

  <!-- ═══════════════════ MARQUEE ═══════════════════ -->
  <div class="ribbon" role="presentation">
    <div class="ribbon-track">
      {#each [...marquee, ...marquee] as item}
        <span class="ribbon-item">
          <span class="ribbon-dot"></span>
          {item}
        </span>
      {/each}
    </div>
  </div>

  <!-- ═══════════════════ THE CAST — Trading Cards ═══════════════════ -->
  <section class="cast" id="cast">
    <header class="section-head">
      <p class="section-eyebrow"><span class="eb-mark"></span>CAST CALL · vol. 1<span class="eb-mark"></span></p>
      <h2 class="section-title">
        Meet the <em>founding</em> three.
      </h2>
      <p class="section-lede">
        Each pet maps to a moment in Codex's lifecycle. They appear, do their job,
        and get out of your way. Hover a card. It moves.
      </p>
    </header>

    <div class="cards">
      {#each cards as c, i}
        <article
          class={`card card-${c.bg}`}
          style={`
            --i:${i};
            --rx:${tilts[i].rx}deg;
            --ry:${tilts[i].ry}deg;
            --sx:${tilts[i].sx}%;
            --sy:${tilts[i].sy}%;
          `}
          class:tilting={tilts[i].on}
          onpointermove={(e) => onCardMove(e, i)}
          onpointerleave={() => onCardLeave(i)}>

          <div class="card-foil" aria-hidden="true"></div>
          <div class="card-glare" aria-hidden="true"></div>

          <header class="card-top">
            <span class="card-no">{c.no}</span>
            <span class="card-type">{c.type}</span>
          </header>

          <div class="card-stage">
            <div class="card-halo"></div>
            <span class="card-edition">★ {c.edition}</span>
            <img src={c.img} alt={c.name} class="card-art" />
            <span class="card-flag">{c.flag}</span>
          </div>

          <div class="card-meta">
            <h3 class="card-name">{c.name}</h3>
            <p class="card-latin"><em>{c.latin}</em></p>
            <p class="card-hook"><code>{c.hook}</code></p>

            <div class="card-tags">
              {#each c.tags as t}
                <span class="card-tag">{t}</span>
              {/each}
            </div>

            <p class="card-flavor">{c.flavor}</p>

            <dl class="stats">
              {#each c.stats as [k, v], si}
                <div class="stat">
                  <dt>{k}</dt>
                  <dd>
                    <span class="bar"><span class="bar-fill" style={`width:${v}%; animation-delay:${i * 120 + si * 80}ms`}></span></span>
                    <span class="bar-n">{v}</span>
                  </dd>
                </div>
              {/each}
            </dl>
          </div>
        </article>
      {/each}
    </div>
  </section>

  <!-- ═══════════════════ A DAY IN THE LIFE ═══════════════════ -->
  <section class="day" id="day">
    <header class="section-head">
      <p class="section-eyebrow"><span class="eb-mark"></span>A DAY IN THE LIFE<span class="eb-mark"></span></p>
      <h2 class="section-title">
        Watch them <em>work</em>.
      </h2>
      <p class="section-lede">Three snapshots from a real Codex thread, narrated by the pets themselves.</p>
    </header>

    <div class="day-rail" aria-hidden="true"></div>

    {#each moments as m, i}
      <article class={`moment moment-${m.tone}`} class:reverse={i === 1}>
        <span class="moment-no" aria-hidden="true">{m.no}</span>
        <div class="moment-art">
          <img src={m.img} alt="" />
        </div>
        <div class="moment-copy">
          <span class="moment-time">{m.time}</span>
          <h3>{m.title}</h3>
          <p>{m.body}</p>
          <p class="moment-hook"><code>hook: {m.hook}</code></p>
        </div>
      </article>
    {/each}
  </section>

  <!-- ═══════════════════ WHY ═══════════════════ -->
  <section class="why" id="why">
    <header class="section-head light">
      <p class="section-eyebrow"><span class="eb-mark light"></span>THE BORING IMPORTANT STUFF<span class="eb-mark light"></span></p>
      <h2 class="section-title light">
        Cute on the surface. <em>Sensible</em> underneath.
      </h2>
    </header>

    <ul class="benefits">
      {#each benefits as b, i}
        <li class="benefit" style={`--i:${i}`}>
          <span class="benefit-emoji" aria-hidden="true">{b.emoji}</span>
          <h3>{b.h}</h3>
          <p>{b.t}</p>
        </li>
      {/each}
    </ul>
  </section>

  <!-- ═══════════════════ ADOPT (Install) ═══════════════════ -->
  <section class="adopt" id="adopt">
    <div class="certificate">
      <div class="cert-corner tl">✦</div>
      <div class="cert-corner tr">✦</div>
      <div class="cert-corner bl">✦</div>
      <div class="cert-corner br">✦</div>

      <header class="cert-head">
        <img src="/artwork/codex-pet-bar-icon.png" alt="" class="cert-icon" />
        <div>
          <p class="cert-eyebrow">CERTIFICATE OF ADOPTION</p>
          <h2>Three lines, six pets, one menu bar.</h2>
        </div>
        <div class="cert-seal" aria-hidden="true">
          <div class="seal-ring"></div>
          <div class="seal-core">
            <span class="seal-l">EST.</span>
            <span class="seal-y">2026</span>
          </div>
        </div>
      </header>

      <pre class="cert-code"><code>{#each installLines as line, i}<span class="code-line"><span class="code-prompt">$</span><span class="code-text">{line}</span></span>{#if i < installLines.length - 1}{"\n"}{/if}{/each}</code></pre>

      <div class="cert-actions">
        <button type="button" class="btn btn-primary" onclick={copy}>
          {copied ? "✓  Copied" : "Copy adoption forms"}
        </button>
        <a class="btn btn-outline" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
          Read the source ↗
        </a>
      </div>

      <p class="cert-fine">
        By installing you agree to feed the pets occasional attention and to forgive any
        rendering glitches on multi-display setups. Requires macOS 13+ and Codex installed.
      </p>
    </div>
  </section>

  <!-- ═══════════════════ FOOTER ═══════════════════ -->
  <footer class="footer">
    <div class="footer-peek" aria-hidden="true">
      <img src="/artwork/codex-pet-bar-hero-trans.png" alt="" />
    </div>
    <div class="footer-content">
      <div>
        <p class="ft-mark"><strong>codex-pet-bar</strong></p>
        <p class="ft-desc">Tiny menu-bar pets for your Codex agent. Open source, MIT.</p>
      </div>
      <nav class="ft-links">
        <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">GitHub</a>
        <a href="https://ajt.dev" target="_blank" rel="noreferrer">ajt.dev</a>
        <a href="/">Original landing</a>
        <a href="/claude">/claude</a>
        <a href="/new">/new</a>
      </nav>
      <p class="ft-end">Made with 🍵 in 🇬🇧 by Andy Tyler · MMXXVI</p>
    </div>
  </footer>

  <!-- Persistent corner buddy -->
  <div class="buddy" aria-hidden="true" style:--lean={`${buddyLean}deg`}>
    <img src="/artwork/moments/running-flame.png" alt="" />
    <span class="buddy-bubble">scroll on, friend</span>
  </div>
</div>

<style>
  /* ================================================================
     PETWORLD — a visual, character-led landing for Codex Pet Bar
     ================================================================ */
  .petworld {
    --cream:    #fff5e4;
    --paper:    #fffaf0;
    --ink:      #1a1428;
    --ink-soft: #4a4360;
    --ink-faint:#867c9d;
    --sky-1:    #ffd0a1;
    --sky-2:    #ffb6c8;
    --sky-3:    #a4c8ff;
    --sun:      #ffcc4a;
    --coral:    #ff5a3c;
    --cobalt:   #1d68ff;
    --forest:   #2da14a;
    --berry:    #b13aff;
    --gold:     #ffb946;
    --shadow:   #1a1428;

    --font-display: "Bricolage Grotesque", "Times New Roman", serif;
    --font-body:    "Plus Jakarta Sans", system-ui, sans-serif;
    --font-mono:    "JetBrains Mono", ui-monospace, monospace;

    position: relative;
    min-height: 100vh;
    color: var(--ink);
    font-family: var(--font-body);
    line-height: 1.55;
    overflow-x: hidden;
    background: var(--cream);
  }
  :global(body:has(.petworld)) { background: var(--cream) !important; margin: 0; }

  .petworld a { color: inherit; }
  ::selection { background: var(--coral); color: white; }

  /* =================== HERO =================== */
  .hero {
    position: relative;
    min-height: 100vh;
    padding: 0 0 clamp(280px, 32vw, 480px);
    overflow: hidden;
  }
  .sky {
    position: absolute; inset: 0;
    background:
      radial-gradient(120% 80% at 80% 10%, var(--sky-1) 0%, transparent 55%),
      radial-gradient(120% 80% at 10% 30%, var(--sky-2) 0%, transparent 55%),
      linear-gradient(180deg, var(--sky-3) 0%, #d4eaff 45%, var(--cream) 92%);
    z-index: 0;
  }
  .sun {
    position: absolute;
    top: 14%; right: 12%;
    width: clamp(140px, 18vw, 240px);
    height: clamp(140px, 18vw, 240px);
    border-radius: 50%;
    background: radial-gradient(circle at 30% 30%, #fff3b0 0%, var(--sun) 60%, #ff9b3a 100%);
    box-shadow:
      0 0 80px rgba(255, 204, 74, 0.6),
      0 0 160px rgba(255, 155, 58, 0.4);
    transform: translate3d(calc(var(--mx, 0) * -10px), calc(var(--my, 0) * -6px), 0);
    transition: transform 200ms ease;
  }
  .cloud {
    position: absolute;
    background: #fff;
    border-radius: 999px;
    opacity: 0.9;
    filter: blur(0.4px);
    box-shadow:
      inset 0 -10px 30px rgba(180, 200, 235, 0.5),
      0 20px 40px rgba(135, 180, 240, 0.25);
  }
  .c1 { top: 22%; left: 6%; width: 180px; height: 50px; }
  .c1::before, .c1::after { content: ""; position: absolute; background: #fff; border-radius: 50%; }
  .c1::before { width: 80px; height: 80px; top: -35px; left: 30px; }
  .c1::after  { width: 60px; height: 60px; top: -22px; left: 90px; }
  .c2 { top: 48%; left: 36%; width: 120px; height: 36px; opacity: 0.7; }
  .c2::before { content: ""; position: absolute; background: #fff; border-radius: 50%; width: 56px; height: 56px; top: -24px; left: 22px; }
  .c3 { top: 12%; left: 50%; width: 90px; height: 26px; opacity: 0.6; }
  .c3::before { content: ""; position: absolute; background: #fff; border-radius: 50%; width: 42px; height: 42px; top: -18px; left: 18px; }

  .topbar {
    position: relative;
    z-index: 4;
    max-width: 1280px;
    margin: 0 auto;
    padding: 22px clamp(20px, 4vw, 48px);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .logo {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    text-decoration: none;
    font-family: var(--font-mono);
    font-size: 13.5px;
    color: var(--ink);
  }
  .logo img {
    width: 36px; height: 36px;
    border-radius: 8px;
    box-shadow: 2px 2px 0 rgba(0,0,0,0.18);
  }
  .logo em { font-style: normal; color: var(--ink-faint); }
  .topnav {
    list-style: none; padding: 0; margin: 0;
    display: flex;
    align-items: center;
    gap: 22px;
    background: rgba(255, 255, 255, 0.55);
    backdrop-filter: blur(8px);
    border: 1.5px solid rgba(26, 20, 40, 0.12);
    padding: 8px 18px;
    border-radius: 999px;
    box-shadow: 0 4px 0 rgba(26, 20, 40, 0.08);
  }
  .topnav a {
    font-size: 14px;
    font-weight: 600;
    text-decoration: none;
    color: var(--ink);
  }
  .topnav a:hover { color: var(--coral); }
  .topnav-gh { background: var(--ink); color: white !important; padding: 6px 12px; border-radius: 999px; }
  .topnav-gh:hover { background: var(--coral); }
  @media (max-width: 760px) { .topnav { display: none; } }

  /* ───── LIVE MENUBAR DEMO ───── */
  .livedemo {
    position: relative;
    z-index: 4;
    max-width: 720px;
    margin: 20px auto 12px;
    padding: 0 clamp(20px, 4vw, 48px);
  }
  .livedemo-bar {
    --tone: #1d68ff;
    height: 38px;
    background: rgba(26, 20, 40, 0.92);
    backdrop-filter: blur(10px);
    color: var(--cream);
    border-radius: 12px;
    border: 2px solid var(--ink);
    box-shadow:
      0 1px 0 rgba(255,255,255,0.05) inset,
      0 10px 26px rgba(26,20,40,0.35);
    padding: 0 12px;
    display: flex;
    align-items: center;
    gap: 12px;
    font-family: var(--font-mono);
    font-size: 12.5px;
    overflow: hidden;
    position: relative;
  }
  .livedemo-bar.tone-blue   { --tone: #5a9eff; }
  .livedemo-bar.tone-orange { --tone: #ff8a4a; }
  .livedemo-bar.tone-green  { --tone: #4eda7a; }
  .ld-apple {
    width: 10px; height: 10px; border-radius: 50%;
    background: var(--cream);
    flex-shrink: 0;
  }
  .ld-app { font-weight: 700; letter-spacing: 0.04em; }
  .ld-spacer { flex: 1; }
  .ld-status {
    display: inline-flex; align-items: center; gap: 6px;
    color: var(--tone);
    transition: color 320ms ease;
  }
  .ld-dot {
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--tone);
    box-shadow: 0 0 0 2px rgba(255,255,255,0.1), 0 0 10px var(--tone);
    animation: livepulse 1.8s ease-in-out infinite;
  }
  @keyframes livepulse {
    0%, 100% { transform: scale(1); opacity: 1; }
    50%      { transform: scale(1.4); opacity: 0.7; }
  }
  .ld-label { letter-spacing: 0.04em; min-width: 100px; }
  .ld-petwrap {
    position: relative;
    width: 32px; height: 32px;
    flex-shrink: 0;
  }
  .ld-pet {
    position: absolute;
    inset: 0;
    width: 100%; height: 100%;
    object-fit: contain;
    opacity: 0;
    transform: translateY(8px) scale(0.85);
    transition: opacity 280ms ease, transform 380ms cubic-bezier(.16,.84,.32,1);
    filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
  }
  .ld-pet.active {
    opacity: 1;
    transform: translateY(-2px) scale(1);
  }
  .ld-meta { color: rgba(255,245,228,0.4); letter-spacing: 0.1em; }
  .ld-clock { font-weight: 700; min-width: 38px; text-align: right; }
  .livedemo-cap {
    text-align: center;
    margin: 8px 0 0;
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--ink-soft);
  }
  .livedemo-cap span { background: rgba(255,255,255,0.6); padding: 2px 8px; border-radius: 6px; }

  .hero-grid {
    position: relative;
    z-index: 3;
    max-width: 1280px;
    margin: clamp(20px, 4vw, 56px) auto 0;
    padding: 0 clamp(20px, 4vw, 48px);
    display: grid;
    grid-template-columns: 1.1fr 1fr;
    gap: 40px;
    align-items: start;
  }
  @media (max-width: 920px) { .hero-grid { grid-template-columns: 1fr; } }

  .kicker {
    display: inline-block;
    font-family: var(--font-mono);
    font-size: 12px;
    padding: 6px 12px;
    background: var(--ink);
    color: white;
    border-radius: 999px;
    margin-bottom: 18px;
    letter-spacing: 0.04em;
  }
  .hero-title {
    font-family: var(--font-display);
    font-weight: 800;
    font-size: clamp(54px, 9.5vw, 132px);
    line-height: 0.92;
    letter-spacing: -0.03em;
    margin: 0 0 22px;
    font-variation-settings: "opsz" 96, "wdth" 95;
  }
  .hero-title .line { display: block; }
  .hero-title .emph {
    font-style: italic;
    color: var(--coral);
    font-weight: 700;
    font-variation-settings: "opsz" 96, "wdth" 95;
  }
  .mounted .hero-title .line {
    opacity: 0;
    transform: translateY(28px);
    animation: lineIn 800ms cubic-bezier(.16,.84,.32,1) forwards;
  }
  .mounted .hero-title .line:nth-child(1) { animation-delay: 100ms; }
  .mounted .hero-title .line:nth-child(2) { animation-delay: 220ms; }
  .mounted .hero-title .line:nth-child(3) { animation-delay: 340ms; }
  @keyframes lineIn {
    to { opacity: 1; transform: translateY(0); }
  }

  .hero-lede {
    font-size: clamp(15px, 1.4vw, 18px);
    line-height: 1.55;
    color: var(--ink-soft);
    max-width: 44ch;
    margin: 0 0 28px;
  }
  .hero-actions {
    display: flex; gap: 12px; flex-wrap: wrap;
    margin-bottom: 22px;
  }

  /* Buttons */
  .btn {
    appearance: none;
    border: 2px solid var(--ink);
    background: white;
    color: var(--ink);
    font-family: var(--font-body);
    font-weight: 700;
    font-size: 16px;
    padding: 14px 20px;
    border-radius: 999px;
    cursor: pointer;
    text-decoration: none;
    display: inline-flex; align-items: center; gap: 10px;
    box-shadow: 4px 4px 0 var(--ink);
    transition: transform 120ms ease, box-shadow 120ms ease;
  }
  .btn:hover { transform: translate(-2px,-2px); box-shadow: 6px 6px 0 var(--ink); }
  .btn:active { transform: translate(2px,2px); box-shadow: 1px 1px 0 var(--ink); }
  .btn-primary { background: var(--coral); color: white; }
  .btn-ghost   { background: transparent; }
  .btn-outline { background: white; }
  .btn-arrow   { font-size: 11px; }

  .hero-meta {
    display: flex; align-items: center; gap: 10px;
    font-size: 13.5px;
    color: var(--ink-soft);
  }
  .dot {
    display: inline-block;
    width: 10px; height: 10px;
    border-radius: 50%;
    background: var(--forest);
    box-shadow: 0 0 0 3px rgba(45,161,74,0.25);
    animation: pulse 2.2s ease-in-out infinite;
  }
  @keyframes pulse { 0%,100% { box-shadow: 0 0 0 3px rgba(45,161,74,0.25); } 50% { box-shadow: 0 0 0 7px rgba(45,161,74,0.08); } }

  /* Floating ID cards */
  .floaters {
    position: relative;
    height: 100%;
    min-height: 380px;
  }
  .id-card {
    position: absolute;
    background: white;
    border: 2px solid var(--ink);
    border-radius: 16px;
    padding: 10px 14px 10px 8px;
    display: flex; align-items: center; gap: 10px;
    box-shadow: 5px 5px 0 var(--ink);
    width: 200px;
    transition: transform 280ms ease;
  }
  .id-card img {
    width: 56px; height: 56px;
    object-fit: contain;
    flex-shrink: 0;
    filter: drop-shadow(0 4px 6px rgba(0,0,0,0.18));
  }
  .idc-h { margin: 0; font-family: var(--font-display); font-weight: 800; font-size: 18px; letter-spacing: 0.02em; }
  .idc-s { margin: 0; font-family: var(--font-mono); font-size: 11.5px; color: var(--ink-faint); }
  .f1 { top: 0;     left: 8%;  transform: rotate(-6deg)  translate3d(calc(var(--mx,0)*8px),  calc(var(--my,0)*8px),  0); }
  .f2 { top: 130px; left: 36%; transform: rotate(4deg)   translate3d(calc(var(--mx,0)*-12px),calc(var(--my,0)*-10px),0); }
  .f3 { top: 250px; left: 14%; transform: rotate(-2deg)  translate3d(calc(var(--mx,0)*6px),  calc(var(--my,0)*-6px), 0); }
  .id-card:hover { transform: rotate(0deg) scale(1.04); }

  /* Cast pile pinned along the hero bottom */
  .hero-cast {
    position: absolute;
    left: 50%;
    bottom: -8%;
    transform: translateX(-50%);
    width: min(1700px, 130vw);
    z-index: 2;
    pointer-events: none;
  }
  .hero-cast img {
    width: 100%;
    height: auto;
    display: block;
    filter: drop-shadow(0 30px 40px rgba(26,20,40,0.35));
    animation: bobBig 6s ease-in-out infinite;
  }
  @keyframes bobBig {
    0%,100% { transform: translateY(0); }
    50%     { transform: translateY(-10px); }
  }

  /* Scroll cue */
  .scroll-cue {
    position: absolute;
    bottom: 18px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 3;
    display: flex; flex-direction: column; align-items: center; gap: 4px;
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--ink-soft);
    pointer-events: none;
  }
  .scroll-arrow {
    font-size: 16px;
    color: var(--ink);
    animation: scrollBounce 1.6s ease-in-out infinite;
  }
  @keyframes scrollBounce {
    0%, 100% { transform: translateY(0); opacity: 0.4; }
    50%      { transform: translateY(6px); opacity: 1; }
  }

  /* =================== RIBBON =================== */
  .ribbon {
    position: relative;
    z-index: 5;
    background: var(--ink);
    color: var(--cream);
    border-top: 3px solid var(--ink);
    border-bottom: 3px solid var(--ink);
    padding: 14px 0;
    overflow: hidden;
    transform: rotate(-1.2deg) scale(1.02);
    margin: -30px 0 60px;
    box-shadow: 0 12px 24px rgba(26,20,40,0.18);
  }
  .ribbon-track {
    display: flex;
    gap: 36px;
    white-space: nowrap;
    animation: marquee 28s linear infinite;
  }
  .ribbon-item {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 18px;
    letter-spacing: 0.06em;
    display: inline-flex;
    align-items: center;
    gap: 16px;
    flex-shrink: 0;
  }
  .ribbon-dot {
    width: 8px; height: 8px;
    background: var(--coral);
    border-radius: 50%;
  }
  @keyframes marquee {
    from { transform: translateX(0); }
    to   { transform: translateX(-50%); }
  }

  /* =================== SECTION HEAD =================== */
  .section-head {
    max-width: 980px;
    margin: 0 auto 56px;
    padding: 0 clamp(20px, 4vw, 48px);
    text-align: center;
  }
  .section-eyebrow {
    font-family: var(--font-mono);
    font-size: 12.5px;
    letter-spacing: 0.16em;
    color: var(--coral);
    margin: 0 0 14px;
    text-transform: uppercase;
    display: inline-flex;
    align-items: center;
    gap: 14px;
    justify-content: center;
  }
  .eb-mark {
    display: inline-block;
    width: 28px;
    height: 1.5px;
    background: var(--coral);
    position: relative;
  }
  .eb-mark::before, .eb-mark::after {
    content: ""; position: absolute;
    width: 5px; height: 5px;
    background: var(--coral);
    border-radius: 50%;
    top: -1.75px;
  }
  .eb-mark::before { left: -4px; }
  .eb-mark::after  { right: -4px; }
  .eb-mark.light { background: var(--gold); }
  .eb-mark.light::before, .eb-mark.light::after { background: var(--gold); }
  .section-head.light .section-eyebrow { color: var(--gold); }

  .section-title {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(40px, 6vw, 72px);
    line-height: 1.02;
    letter-spacing: -0.025em;
    margin: 0 0 18px;
    font-variation-settings: "opsz" 96, "wdth" 95;
  }
  .section-title em {
    font-style: italic;
    color: var(--coral);
    font-weight: 600;
  }
  .section-title.light em { color: var(--gold); }
  .section-lede {
    font-size: 17px;
    color: var(--ink-soft);
    max-width: 60ch;
    margin: 0 auto;
  }

  /* =================== CARDS =================== */
  .cast {
    padding: 30px 0 100px;
    background:
      radial-gradient(ellipse at 50% 0%, rgba(255,204,74,0.16) 0%, transparent 60%),
      var(--cream);
  }
  .cards {
    max-width: 1280px;
    margin: 0 auto;
    padding: 0 clamp(20px, 4vw, 48px);
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 28px;
    perspective: 1400px;
  }
  @media (max-width: 980px) { .cards { grid-template-columns: 1fr; max-width: 460px; } }

  .card {
    --card-bg-1: #f5d27a;
    --card-bg-2: #ffb86b;
    --card-accent: var(--coral);
    --rx: 0deg; --ry: 0deg; --sx: 50%; --sy: 50%;

    position: relative;
    background: linear-gradient(160deg, var(--card-bg-1), var(--card-bg-2));
    border: 3px solid var(--ink);
    border-radius: 28px;
    padding: 20px;
    box-shadow:
      8px 8px 0 var(--ink),
      0 30px 50px -30px rgba(26,20,40,0.5);
    transform-style: preserve-3d;
    transform:
      rotate(calc(var(--i, 0) * 0.6deg - 0.6deg))
      perspective(900px)
      rotateX(var(--rx))
      rotateY(var(--ry));
    transition: transform 320ms cubic-bezier(.16,.84,.32,1), box-shadow 320ms;
    cursor: grab;
    overflow: hidden;
  }
  .card.tilting {
    transition: transform 80ms ease-out, box-shadow 320ms;
    transform:
      rotate(0deg)
      perspective(900px)
      rotateX(var(--rx))
      rotateY(var(--ry))
      translate(-2px, -6px);
    box-shadow:
      14px 16px 0 var(--ink),
      0 40px 60px -30px rgba(26,20,40,0.6);
  }
  .card-rock  { --card-bg-1: #c8d2dd; --card-bg-2: #94a8c4; --card-accent: var(--cobalt); }
  .card-flame { --card-bg-1: #ffd28a; --card-bg-2: #ff8a4a; --card-accent: var(--coral); }
  .card-ajt   { --card-bg-1: #ffe6a3; --card-bg-2: #ffb04a; --card-accent: var(--gold); }

  /* Holographic foil layer */
  .card-foil {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background:
      conic-gradient(from calc(var(--sx) * 3.6deg) at var(--sx) var(--sy),
        rgba(255, 80, 200, 0.55) 0deg,
        rgba(120, 180, 255, 0.55) 90deg,
        rgba(180, 255, 140, 0.55) 180deg,
        rgba(255, 220, 100, 0.55) 270deg,
        rgba(255, 80, 200, 0.55) 360deg);
    mix-blend-mode: color-dodge;
    opacity: 0;
    pointer-events: none;
    transition: opacity 260ms ease;
    z-index: 4;
  }
  .card-glare {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background:
      radial-gradient(circle at var(--sx) var(--sy),
        rgba(255, 255, 255, 0.55) 0%,
        rgba(255, 255, 255, 0) 35%);
    mix-blend-mode: overlay;
    opacity: 0;
    pointer-events: none;
    transition: opacity 220ms ease;
    z-index: 5;
  }
  .card.tilting .card-foil  { opacity: 0.55; }
  .card.tilting .card-glare { opacity: 1; }

  .card-top {
    display: flex; justify-content: space-between; align-items: center;
    font-family: var(--font-mono);
    font-size: 12px;
    color: var(--ink);
    margin-bottom: 8px;
    position: relative;
    z-index: 2;
  }
  .card-type {
    background: var(--ink);
    color: white;
    padding: 3px 10px;
    border-radius: 999px;
    letter-spacing: 0.06em;
    font-weight: 700;
  }

  .card-stage {
    position: relative;
    background: white;
    border: 2px solid var(--ink);
    border-radius: 20px;
    height: 280px;
    display: grid;
    place-items: center;
    overflow: hidden;
    box-shadow: inset 0 -8px 24px rgba(26,20,40,0.08);
    z-index: 2;
    transform: translateZ(20px);
  }
  .card-halo {
    position: absolute;
    width: 110%;
    height: 100%;
    background: radial-gradient(circle at 50% 60%, var(--card-accent) 0%, transparent 55%);
    opacity: 0.25;
    transition: transform 260ms ease;
  }
  .card-art {
    position: relative;
    max-width: 88%;
    max-height: 88%;
    object-fit: contain;
    z-index: 2;
    filter: drop-shadow(0 16px 18px rgba(26,20,40,0.22));
    transition: transform 280ms cubic-bezier(.16,.84,.32,1);
  }
  .card.tilting .card-art { transform: translateY(-12px) scale(1.06) rotate(-2deg); }
  .card.tilting .card-halo { transform: scale(1.15); }
  .card-flag {
    position: absolute;
    top: 12px; left: 12px;
    background: var(--ink);
    color: white;
    font-family: var(--font-mono);
    font-size: 11px;
    padding: 4px 10px;
    border-radius: 999px;
    letter-spacing: 0.06em;
    z-index: 3;
  }
  .card-edition {
    position: absolute;
    top: 12px; right: 12px;
    background: white;
    color: var(--ink);
    border: 1.5px solid var(--ink);
    font-family: var(--font-mono);
    font-size: 10px;
    padding: 3px 8px;
    border-radius: 4px;
    letter-spacing: 0.1em;
    font-weight: 700;
    z-index: 3;
    transform: rotate(6deg);
  }

  .card-meta {
    padding-top: 18px;
    position: relative;
    z-index: 2;
    transform: translateZ(12px);
  }
  .card-name {
    font-family: var(--font-display);
    font-weight: 800;
    font-size: 36px;
    margin: 0 0 2px;
    color: var(--ink);
    letter-spacing: -0.02em;
  }
  .card-latin {
    margin: 0 0 6px;
    font-style: italic;
    font-size: 14px;
    color: var(--ink-soft);
  }
  .card-hook {
    margin: 0 0 12px;
    font-family: var(--font-mono);
    font-size: 11.5px;
  }
  .card-hook code {
    background: rgba(26,20,40,0.85);
    color: var(--cream);
    padding: 3px 8px;
    border-radius: 6px;
  }
  .card-tags {
    display: flex; flex-wrap: wrap; gap: 6px;
    margin: 0 0 14px;
  }
  .card-tag {
    font-family: var(--font-mono);
    font-size: 10.5px;
    padding: 3px 8px;
    background: white;
    border: 1.5px solid var(--ink);
    border-radius: 6px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    font-weight: 700;
  }
  .card-flavor {
    margin: 0 0 16px;
    font-size: 14.5px;
    line-height: 1.5;
    color: var(--ink);
  }

  .stats { margin: 0; display: grid; gap: 8px; }
  .stat { display: grid; grid-template-columns: 90px 1fr; gap: 12px; align-items: center; font-size: 12px; }
  .stat dt {
    font-family: var(--font-mono);
    color: var(--ink);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .stat dd { margin: 0; display: flex; align-items: center; gap: 8px; }
  .bar {
    flex: 1;
    height: 10px;
    background: rgba(26,20,40,0.18);
    border: 1.5px solid var(--ink);
    border-radius: 999px;
    overflow: hidden;
  }
  .bar-fill {
    display: block;
    height: 100%;
    background: var(--ink);
    border-radius: 999px;
    transform-origin: left center;
    animation: barIn 900ms cubic-bezier(.16,.84,.32,1) both;
  }
  @keyframes barIn {
    from { transform: scaleX(0); }
    to   { transform: scaleX(1); }
  }
  .bar-n {
    font-family: var(--font-mono);
    color: var(--ink);
    min-width: 28px;
    text-align: right;
    font-weight: 700;
  }

  /* =================== DAY IN THE LIFE =================== */
  .day {
    padding: 80px 0 100px;
    background:
      linear-gradient(180deg, var(--cream) 0%, #fff0d9 100%);
    position: relative;
  }
  .day-rail {
    position: absolute;
    left: 50%; top: 240px; bottom: 100px;
    width: 4px;
    background-image: linear-gradient(to bottom, var(--ink) 50%, transparent 50%);
    background-size: 4px 16px;
    opacity: 0.18;
    transform: translateX(-50%);
    pointer-events: none;
  }
  @media (max-width: 980px) { .day-rail { display: none; } }

  .moment {
    max-width: 1180px;
    margin: 60px auto;
    padding: clamp(28px, 4vw, 56px);
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: clamp(20px, 4vw, 48px);
    align-items: center;
    border: 3px solid var(--ink);
    border-radius: 36px;
    box-shadow: 10px 10px 0 var(--ink);
    position: relative;
    overflow: hidden;
  }
  .moment.reverse { direction: rtl; }
  .moment.reverse > *:not(.moment-no) { direction: ltr; }
  @media (max-width: 860px) {
    .moment, .moment.reverse { grid-template-columns: 1fr; direction: ltr; }
  }
  .moment-rock  { background: linear-gradient(135deg, #c8d8ff 0%, #e1ecff 100%); }
  .moment-flame { background: linear-gradient(135deg, #ffd49a 0%, #ffe6c2 100%); }
  .moment-ajt   { background: linear-gradient(135deg, #ffb086 0%, #ffd0a8 100%); }

  /* Big outlined number plate in the corner */
  .moment-no {
    position: absolute;
    top: -40px;
    right: -10px;
    font-family: var(--font-display);
    font-weight: 800;
    font-size: clamp(180px, 22vw, 320px);
    line-height: 1;
    letter-spacing: -0.06em;
    color: transparent;
    -webkit-text-stroke: 2.5px var(--ink);
    opacity: 0.16;
    pointer-events: none;
    z-index: 0;
    font-variation-settings: "opsz" 96, "wdth" 75;
    direction: ltr;
  }
  .moment.reverse .moment-no { right: auto; left: -10px; }

  .moment-art {
    aspect-ratio: 1 / 1;
    display: grid; place-items: center;
    background: rgba(255,255,255,0.6);
    border: 2px solid var(--ink);
    border-radius: 24px;
    padding: 24px;
    position: relative;
    z-index: 1;
  }
  .moment-art img {
    width: 78%;
    height: auto;
    filter: drop-shadow(0 20px 24px rgba(26,20,40,0.25));
    animation: bobMed 5s ease-in-out infinite;
  }
  @keyframes bobMed {
    0%,100% { transform: translateY(0) rotate(-1deg); }
    50%     { transform: translateY(-12px) rotate(1deg); }
  }
  .moment-copy { position: relative; z-index: 1; }
  .moment-time {
    display: inline-block;
    font-family: var(--font-mono);
    font-size: 12px;
    padding: 5px 12px;
    background: var(--ink);
    color: white;
    border-radius: 999px;
    letter-spacing: 0.04em;
    margin-bottom: 14px;
  }
  .moment-copy h3 {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(28px, 4vw, 48px);
    line-height: 1.05;
    margin: 0 0 14px;
    letter-spacing: -0.02em;
  }
  .moment-copy p {
    margin: 0 0 12px;
    font-size: 17px;
    line-height: 1.55;
    color: var(--ink);
    max-width: 44ch;
  }
  .moment-copy em { font-style: italic; color: var(--coral); }
  .moment-hook code {
    font-family: var(--font-mono);
    font-size: 12.5px;
    background: var(--ink);
    color: var(--cream);
    padding: 5px 10px;
    border-radius: 8px;
    display: inline-block;
    margin-top: 4px;
  }

  /* =================== WHY =================== */
  .why {
    padding: 100px 0 120px;
    background: var(--ink);
    color: var(--cream);
    position: relative;
  }
  .why::before {
    content: ""; position: absolute;
    inset: 0;
    background-image:
      radial-gradient(circle at 20% 30%, rgba(255,204,74,0.08) 0, transparent 40%),
      radial-gradient(circle at 80% 70%, rgba(255,90,60,0.10) 0, transparent 40%);
    pointer-events: none;
  }
  .section-title.light { color: var(--cream); }
  .benefits {
    list-style: none;
    padding: 0; margin: 0;
    max-width: 1180px;
    padding-inline: clamp(20px, 4vw, 48px);
    margin-inline: auto;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 18px;
    position: relative;
  }
  @media (max-width: 920px) { .benefits { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 520px) { .benefits { grid-template-columns: 1fr; } }
  .benefit {
    background: var(--cream);
    color: var(--ink);
    border-radius: 20px;
    padding: 22px;
    border: 3px solid var(--ink);
    box-shadow: 6px 6px 0 var(--gold);
    transform: rotate(calc((var(--i, 0) - 1.5) * 1deg));
    transition: transform 220ms ease, box-shadow 220ms ease;
  }
  .benefit:nth-child(2n) { box-shadow: 6px 6px 0 var(--coral); }
  .benefit:hover {
    transform: rotate(0) translate(-2px,-3px);
    box-shadow: 8px 9px 0 var(--gold);
  }
  .benefit:nth-child(2n):hover { box-shadow: 8px 9px 0 var(--coral); }
  .benefit-emoji {
    font-size: 36px;
    display: block;
    margin-bottom: 6px;
  }
  .benefit h3 {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 20px;
    margin: 0 0 6px;
  }
  .benefit p {
    margin: 0;
    font-size: 14.5px;
    color: var(--ink-soft);
    line-height: 1.5;
  }

  /* =================== ADOPT =================== */
  .adopt {
    padding: 100px clamp(20px, 4vw, 48px);
    background:
      radial-gradient(ellipse at 50% 30%, #ffe6a3 0%, transparent 60%),
      var(--cream);
  }
  .certificate {
    position: relative;
    max-width: 880px;
    margin: 0 auto;
    background: var(--paper);
    border: 3px solid var(--ink);
    border-radius: 32px;
    padding: clamp(32px, 5vw, 56px);
    box-shadow: 12px 12px 0 var(--coral);
  }
  .cert-corner {
    position: absolute;
    width: 28px; height: 28px;
    display: grid; place-items: center;
    background: var(--coral);
    color: white;
    border: 3px solid var(--ink);
    border-radius: 50%;
    font-size: 14px;
  }
  .cert-corner.tl { top: -16px; left: -16px; }
  .cert-corner.tr { top: -16px; right: -16px; }
  .cert-corner.bl { bottom: -16px; left: -16px; }
  .cert-corner.br { bottom: -16px; right: -16px; }

  .cert-head {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: 22px;
    margin-bottom: 26px;
    border-bottom: 2px dashed var(--ink-faint);
    padding-bottom: 22px;
  }
  @media (max-width: 640px) { .cert-head { grid-template-columns: auto 1fr; } .cert-seal { display: none; } }
  .cert-icon {
    width: 84px; height: 84px;
    border-radius: 18px;
    box-shadow: 4px 4px 0 var(--ink);
    flex-shrink: 0;
  }
  .cert-eyebrow {
    font-family: var(--font-mono);
    font-size: 12px;
    color: var(--coral);
    letter-spacing: 0.16em;
    margin: 0 0 4px;
    text-transform: uppercase;
  }
  .cert-head h2 {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: clamp(24px, 3vw, 36px);
    line-height: 1.1;
    margin: 0;
    letter-spacing: -0.02em;
  }
  .cert-seal {
    position: relative;
    width: 90px; height: 90px;
  }
  .seal-ring {
    position: absolute; inset: 0;
    border: 2.5px dashed var(--coral);
    border-radius: 50%;
    animation: sealspin 22s linear infinite;
  }
  .seal-ring::before {
    content: ""; position: absolute; inset: 6px;
    border: 2px solid var(--coral);
    border-radius: 50%;
  }
  @keyframes sealspin { to { transform: rotate(360deg); } }
  .seal-core {
    position: absolute; inset: 0;
    display: grid; place-content: center; text-align: center;
    color: var(--coral);
    font-family: var(--font-display);
    line-height: 1;
  }
  .seal-l { font-size: 11px; letter-spacing: 0.18em; }
  .seal-y { font-size: 26px; font-weight: 800; }

  .cert-code {
    background: var(--ink);
    color: var(--cream);
    font-family: var(--font-mono);
    font-size: 14px;
    line-height: 1.8;
    padding: 22px 26px;
    border-radius: 16px;
    margin: 0 0 22px;
    overflow-x: auto;
    border: 2px solid var(--ink);
    box-shadow: inset 0 0 0 2px #2a2440;
  }
  .code-line { display: block; }
  .code-prompt { color: var(--coral); margin-right: 12px; user-select: none; }
  .code-text { color: var(--cream); }
  .cert-actions {
    display: flex; gap: 12px; flex-wrap: wrap;
    margin-bottom: 18px;
  }
  .cert-fine {
    font-size: 12.5px;
    color: var(--ink-faint);
    margin: 0;
    font-style: italic;
    line-height: 1.5;
  }

  /* =================== FOOTER =================== */
  .footer {
    position: relative;
    background: var(--ink);
    color: var(--cream);
    padding: 200px clamp(20px, 4vw, 48px) 36px;
    overflow: hidden;
    margin-top: 60px;
  }
  .footer-peek {
    position: absolute;
    top: 0; left: 50%;
    transform: translate(-50%, -55%);
    width: min(1600px, 130vw);
    pointer-events: none;
    z-index: 1;
  }
  .footer-peek img {
    width: 100%; height: auto; display: block;
    filter: drop-shadow(0 -20px 30px rgba(0,0,0,0.4));
  }
  .footer-content {
    position: relative;
    z-index: 2;
    max-width: 1180px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1.4fr 1fr;
    gap: 30px;
    align-items: end;
  }
  @media (max-width: 720px) {
    .footer-content { grid-template-columns: 1fr; }
  }
  .ft-mark {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 28px;
    margin: 0 0 6px;
  }
  .ft-desc {
    margin: 0;
    font-size: 14.5px;
    color: rgba(255,245,228,0.65);
    max-width: 38ch;
  }
  .ft-links {
    display: flex; flex-wrap: wrap; gap: 18px;
    justify-content: flex-end;
  }
  .ft-links a {
    text-decoration: none;
    color: var(--cream);
    font-weight: 600;
    border-bottom: 2px dotted rgba(255,245,228,0.4);
  }
  .ft-links a:hover { color: var(--gold); border-bottom-color: var(--gold); }
  .ft-end {
    grid-column: 1 / -1;
    margin: 30px 0 0;
    text-align: center;
    color: rgba(255,245,228,0.4);
    font-family: var(--font-mono);
    font-size: 12px;
    border-top: 1px solid rgba(255,245,228,0.12);
    padding-top: 20px;
    letter-spacing: 0.04em;
  }

  /* =================== CORNER BUDDY =================== */
  .buddy {
    position: fixed;
    bottom: 18px;
    left: 18px;
    z-index: 50;
    display: flex;
    align-items: center;
    gap: 10px;
    pointer-events: none;
    transform: translateY(0);
  }
  .buddy img {
    width: 64px; height: 64px;
    object-fit: contain;
    filter: drop-shadow(0 6px 10px rgba(0,0,0,0.35));
    animation: bobMed 3.2s ease-in-out infinite;
    transform: rotate(var(--lean, 0deg));
    transition: transform 280ms cubic-bezier(.2,.7,.2,1);
  }
  .buddy-bubble {
    background: var(--cream);
    color: var(--ink);
    border: 2px solid var(--ink);
    border-radius: 16px;
    padding: 6px 12px;
    font-size: 13px;
    font-weight: 600;
    font-family: var(--font-body);
    box-shadow: 3px 3px 0 var(--ink);
    position: relative;
    opacity: 0;
    transform: translateX(-8px);
    animation: bubbleIn 600ms ease-out 1400ms forwards;
  }
  .buddy-bubble::before {
    content: "";
    position: absolute;
    left: -7px; top: 50%;
    transform: translateY(-50%) rotate(45deg);
    width: 10px; height: 10px;
    background: var(--cream);
    border-left: 2px solid var(--ink);
    border-bottom: 2px solid var(--ink);
  }
  @keyframes bubbleIn {
    to { opacity: 1; transform: translateX(0); }
  }
  @media (max-width: 720px) {
    .buddy-bubble { display: none; }
    .buddy { bottom: 12px; left: 12px; }
  }

  @media (prefers-reduced-motion: reduce) {
    .hero-cast img, .moment-art img, .ribbon-track, .sun, .id-card, .dot,
    .hero-title .line, .ld-dot, .scroll-arrow, .seal-ring, .buddy img,
    .bar-fill { animation: none !important; transform: none !important; }
    .mounted .hero-title .line { opacity: 1; }
  }
</style>

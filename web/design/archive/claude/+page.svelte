<script lang="ts">
  import { onMount } from "svelte";

  const installCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";
  const installSteps = installCommand.split("\n");

  let copied = $state(false);
  let resetTimer: ReturnType<typeof setTimeout> | undefined;
  let scrollY = $state(0);
  let mounted = $state(false);

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
    const onScroll = () => (scrollY = window.scrollY);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      clearTimeout(resetTimer);
    };
  });

  const specimens = [
    {
      plate: "II",
      number: "001",
      name: "Petrosus statusbarensis",
      common: "The Rock",
      epithet: "Sentinel of the Threshold",
      img: "/artwork/moments/approval-rock.png",
      hook: "PermissionRequest · permission_requested",
      habit: "Surfaces a small Codex flag the instant the agent pauses for human consent. Holds perfectly still until acknowledged.",
      taxonomy: [
        ["Order", "Mineralia"],
        ["Disposition", "Patient"],
        ["Coloration", "Granite, banded"],
        ["First sighted", "Approvals queue"],
      ],
      note: "Often mistaken for an inert rock until the moment of decision, when it becomes the most attentive creature in the bar.",
      tint: "ochre",
    },
    {
      plate: "III",
      number: "002",
      name: "Ignis cursoria",
      common: "The Flame",
      epithet: "Runner of the Tool-Use",
      img: "/artwork/moments/running-flame.png",
      hook: "PreToolUse · tool_started",
      habit: "Trots steadily across the bar while Codex edits, searches, or shells out. The longer the task, the more deliberate the gait.",
      taxonomy: [
        ["Order", "Caloria"],
        ["Disposition", "Restless"],
        ["Coloration", "Amber to cinder"],
        ["First sighted", "Edit hooks, mid-flight"],
      ],
      note: "A reliable indicator that work is in motion. Do not feed during execution — disrupts the cadence.",
      tint: "ember",
    },
    {
      plate: "IV",
      number: "003",
      name: "Festivus completionis",
      common: "AJT",
      epithet: "Bearer of the Finish Line",
      img: "/artwork/moments/completed-ajt.png",
      hook: "PostToolUse · stopped",
      habit: "Settles, then permits itself a small celebratory motion when the thread concludes. The only creature that consistently looks satisfied.",
      taxonomy: [
        ["Order", "Conclusiva"],
        ["Disposition", "Contented"],
        ["Coloration", "Fresh ink"],
        ["First sighted", "End-of-thread"],
      ],
      note: "Reportedly the favourite of long-running operators; appears most often after a difficult migration.",
      tint: "verdigris",
    },
  ];

  const provenance = [
    { k: "I.", h: "Strictly local", t: "Hooks read Codex activity from disk and write small status updates beneath ~/.codex. Nothing leaves the machine." },
    { k: "II.", h: "No background cloud", t: "A macOS menu-bar utility, not a hosted service. There is no account, no server, no telemetry pipe." },
    { k: "III.", h: "Hackable pets", t: "Each creature is a package on disk. Inspect them, mutate them, or commission your own — the format is yours." },
    { k: "IV.", h: "MIT, in the open", t: "Made by Andy Tyler for operators who like to hack on their tooling. Issues and pull requests welcome." },
  ];
</script>

<svelte:head>
  <title>The Petdex — A Field Guide to Menu Bar Companions</title>
  <meta
    name="description"
    content="Tiny pets that listen to local Codex activity, react to approvals, and make each thread legible at a glance. An illustrated field guide." />
  <meta property="og:title" content="The Petdex — A Field Guide to Menu Bar Companions" />
  <meta property="og:description" content="Tiny pets that listen to local Codex activity, react to approvals, and make each thread legible at a glance. An illustrated field guide." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-petdex.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:alt" content="Petdex field-guide social card showing menu-bar companion pets on an illustrated plate." />
  <meta name="twitter:title" content="The Petdex — A Field Guide to Menu Bar Companions" />
  <meta name="twitter:description" content="Tiny pets that listen to local Codex activity, react to approvals, and make each thread legible at a glance. An illustrated field guide." />
  <meta name="twitter:image" content="/artwork/open-graph/codex-pet-bar-og-petdex.png" />
  <meta name="twitter:image:alt" content="Petdex field-guide social card showing menu-bar companion pets on an illustrated plate." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght,SOFT,WONK@0,9..144,300..900,0..100,0..1;1,9..144,300..900,0..100,0..1&family=JetBrains+Mono:ital,wght@0,300..800;1,300..800&display=swap"
    rel="stylesheet" />
</svelte:head>

<div class="petdex" class:mounted>
  <!-- Paper grain & vignette -->
  <div class="paper-grain" aria-hidden="true"></div>
  <div class="paper-edge" aria-hidden="true"></div>

  <!-- ░░ MASTHEAD ░░ -->
  <header class="masthead">
    <div class="rule rule-double"></div>

    <div class="masthead-row top">
      <span class="meta-tag">Vol. I · № 03</span>
      <span class="meta-tag center">Est. MMXXVI · Published in 🇬🇧</span>
      <span class="meta-tag right">A specimen catalogue</span>
    </div>

    <div class="rule rule-thin"></div>

    <h1 class="wordmark">
      <span class="wm-the">The</span>
      <span class="wm-main">Petdex</span>
    </h1>

    <p class="tagline">
      <span class="ornament">❦</span>
      <em>A Field Guide</em>
      &nbsp;to the Menu Bar Companions of&nbsp;
      <span class="caps">Codex</span>
      <span class="ornament">❦</span>
    </p>

    <div class="rule rule-thin"></div>

    <div class="masthead-row bottom">
      <span class="meta-tag">Illustrated &middot; Annotated</span>
      <span class="meta-tag center mono">macOS · menu-bar · local-only</span>
      <span class="meta-tag right">
        <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">github / andytyler</a>
      </span>
    </div>

    <div class="rule rule-double"></div>
  </header>

  <!-- ░░ ESTABLISHING PLATE ░░ -->
  <section class="plate-establishing">
    <aside class="margin-left">
      <p class="margin-note">
        <span class="margin-num">i.</span>
        Observed in their native habitat — the upper-right margin of a 14-inch laptop, between
        <span class="caps">Wi-Fi</span> and battery glyph.
      </p>
      <p class="margin-note">
        <span class="margin-num">ii.</span>
        Specimens listen passively to <span class="mono">~/.codex</span> events and surface only when a hook fires.
      </p>
      <p class="margin-note">
        <span class="margin-num">iii.</span>
        No two collections alike. Pets are filesystem packages: inspect, fork, replace at will.
      </p>
    </aside>

    <figure class="plate-figure">
      <div class="plate-stamp">
        <span class="plate-label">Plate</span>
        <span class="plate-roman">I</span>
      </div>
      <div class="vitrine">
        <div class="vitrine-glass" aria-hidden="true"></div>
        <img src="/artwork/codex-pet-bar-hero-trans.png" alt="A line-up of menu-bar pets" class="plate-img float" />
        <div class="vitrine-shelf" aria-hidden="true"></div>
      </div>
      <figcaption>
        <span class="caps">Fig. 1</span> — A representative menagerie, displayed in repose along the operator's bar.
        Distance between specimens has been exaggerated for clarity.
      </figcaption>
    </figure>

    <aside class="margin-right">
      <div class="install-card">
        <div class="ic-head">
          <span class="caps">The Field Kit</span>
          <span class="ic-sigil">¶</span>
        </div>
        <p class="ic-desc">Clone the repository, then run the installer. Three lines.</p>
        <pre class="ic-code"><code>{#each installSteps as line, i}<span class="ic-line"><span class="ic-prompt">$</span><span class="ic-cmd">{line}</span></span>{#if i < installSteps.length - 1}{"\n"}{/if}{/each}</code></pre>
        <div class="ic-actions">
          <button class="btn-ink" onclick={copy} aria-live="polite">
            {copied ? "✓  Copied to clipboard" : "Copy procedure"}
          </button>
          <a class="btn-ghost" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">Read the source ↗</a>
        </div>
      </div>
    </aside>
  </section>

  <!-- ░░ ABSTRACT ░░ -->
  <section class="abstract">
    <div class="rule rule-leaf">
      <span class="rule-leaf-glyph">❧</span>
    </div>
    <h2 class="section-title">From the Editor</h2>
    <div class="abstract-cols">
      <p class="ab-col drop-cap">
        Most software speaks in notifications: rectangular, urgent, and forgettable. The
        <em>Petdex</em> proposes a quieter compact — that the small creatures who attend your work
        ought to <em>be seen, briefly</em>, and then return to stillness. Each specimen catalogued
        in these pages corresponds to a single lifecycle hook: a moment in the life of a
        <span class="caps">Codex</span> thread that benefits from being legible at a glance.
      </p>
      <p class="ab-col">
        We have chosen illustration over instrumentation. A flame, briskly running, conveys what a
        progress bar cannot — that the work is alive. A rock holding a flag tells the operator more
        about the pause for consent than any modal. These are not characters in the marketing
        sense; they are <em>peripheral instruments</em>, calibrated for the corner of the eye.
        What follows is the current catalogue, in order of discovery.
      </p>
    </div>
    <div class="rule rule-leaf">
      <span class="rule-leaf-glyph">❧</span>
    </div>
  </section>

  <!-- ░░ TABLE OF SPECIMENS (TOC) ░░ -->
  <section class="toc">
    <div class="toc-head">
      <span class="caps">Index of Specimens</span>
      <span class="toc-flourish">— iii —</span>
    </div>
    <ol class="toc-list">
      {#each specimens as s}
        <li class="toc-item">
          <span class="toc-num">{s.number}</span>
          <a href={`#specimen-${s.number}`} class="toc-name">
            <span class="toc-latin">{s.name}</span>
            <span class="toc-dots" aria-hidden="true"></span>
            <span class="toc-common">{s.common}</span>
          </a>
          <span class="toc-page">PL. {s.plate}</span>
        </li>
      {/each}
    </ol>
  </section>

  <!-- ░░ SPECIMEN ENTRIES ░░ -->
  {#each specimens as s, i}
    <section class={`specimen tint-${s.tint}`} id={`specimen-${s.number}`}>
      <header class="sp-head">
        <div class="sp-plate">
          <span class="sp-plate-l">Plate</span>
          <span class="sp-plate-n">{s.plate}</span>
        </div>
        <div class="sp-titleblock">
          <p class="sp-number"><span class="caps">Specimen</span> · № {s.number}</p>
          <h2 class="sp-latin"><em>{s.name}</em></h2>
          <p class="sp-common">
            “{s.common}” — <span class="sp-epithet">{s.epithet}</span>
          </p>
        </div>
        <div class="sp-stamp" aria-hidden="true">
          <div class="stamp-ring">
            <span class="stamp-text">CATALOGUED · CODEX HOOK · CATALOGUED · CODEX HOOK ·</span>
          </div>
          <span class="stamp-core">№<br /><strong>{s.number}</strong></span>
        </div>
      </header>

      <div class="sp-body">
        <figure class="sp-figure">
          <div class="sp-illus-frame">
            <img src={s.img} alt={s.common} class="sp-illus" />
          </div>
          <figcaption><span class="caps">Fig. {s.plate}.a</span> — Illustration after life.</figcaption>
        </figure>

        <div class="sp-notes">
          <p class="sp-hook mono">
            <span class="sp-hook-label">Hook</span>
            <span class="sp-hook-value">{s.hook}</span>
          </p>

          <h3 class="sp-h3">Habit &amp; Behaviour</h3>
          <p class="sp-text">{s.habit}</p>

          <h3 class="sp-h3">Taxonomic Notes</h3>
          <dl class="sp-dl">
            {#each s.taxonomy as [k, v]}
              <div class="sp-dl-row">
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            {/each}
          </dl>

          <p class="sp-margin">
            <span class="margin-num">¶</span>
            <em>{s.note}</em>
          </p>
        </div>
      </div>

      {#if i < specimens.length - 1}
        <div class="rule rule-ornament">
          <span class="rule-ornament-glyph">§</span>
        </div>
      {/if}
    </section>
  {/each}

  <!-- ░░ PROVENANCE ░░ -->
  <section class="provenance">
    <div class="rule rule-double"></div>
    <h2 class="section-title">Provenance &amp; Conduct</h2>
    <p class="prov-lede">
      A short statement of where these creatures come from, where they sleep, and what is asked of them.
    </p>

    <ol class="prov-grid">
      {#each provenance as p}
        <li class="prov-item">
          <span class="prov-roman">{p.k}</span>
          <h3 class="prov-h">{p.h}</h3>
          <p class="prov-t">{p.t}</p>
        </li>
      {/each}
    </ol>

    <div class="rule rule-double"></div>
  </section>

  <!-- ░░ COLOPHON ░░ -->
  <footer class="colophon">
    <div class="col-grid">
      <div>
        <p class="caps small">Colophon</p>
        <p class="col-body">
          Set in <em>Fraunces</em> (opsz 9–144) and <span class="mono">JetBrains Mono</span>. Printed digitally,
          on parchment-cream <span class="mono">oklch(0.96 0.02 80)</span>. The masthead is hand-set;
          the marginalia is hand-written.
        </p>
      </div>
      <div>
        <p class="caps small">Imprint</p>
        <p class="col-body">
          The <em>Petdex</em> is open source under the <span class="caps">MIT</span> licence and
          maintained by <a href="https://ajt.dev" target="_blank" rel="noreferrer">Andy Tyler</a>.
          Issues, observations, and new specimens may be submitted on
          <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">GitHub</a>.
        </p>
      </div>
      <div>
        <p class="caps small">Return</p>
        <p class="col-body">
          <a href="#top">↑ to the masthead</a><br />
          <a href="/">⟵ to the original site</a>
        </p>
      </div>
    </div>
    <div class="rule rule-double"></div>
    <p class="col-end">— Finis —</p>
  </footer>
</div>

<style>
  /* ============================================================
     PALETTE & TYPE SYSTEM — The Petdex
     ============================================================ */
  .petdex {
    --paper:        oklch(0.96 0.022 80);   /* warm parchment */
    --paper-deep:   oklch(0.93 0.030 78);   /* shadowed parchment */
    --ink:          oklch(0.21 0.030 50);   /* deep brown-black */
    --ink-soft:     oklch(0.36 0.028 50);
    --ink-faint:    oklch(0.55 0.020 60);
    --oxblood:      oklch(0.44 0.150 28);   /* signature accent */
    --verdigris:    oklch(0.50 0.060 170);
    --ochre:        oklch(0.62 0.140 70);
    --ember:        oklch(0.55 0.180 40);
    --rule:         oklch(0.40 0.025 50);

    --font-display: "Fraunces", "Times New Roman", serif;
    --font-body:    "Fraunces", "Iowan Old Style", Georgia, serif;
    --font-mono:    "JetBrains Mono", "SF Mono", ui-monospace, monospace;

    position: relative;
    min-height: 100vh;
    color: var(--ink);
    background: var(--paper);
    font-family: var(--font-body);
    font-feature-settings: "ss01", "ss02", "onum", "liga";
    font-variation-settings: "opsz" 14, "SOFT" 50;
    line-height: 1.55;
    overflow-x: hidden;
  }

  /* Override host body background so the parchment dominates */
  :global(body:has(.petdex)) {
    background: oklch(0.96 0.022 80) !important;
  }

  /* ░░ PAPER ░░ */
  .paper-grain {
    position: fixed; inset: 0; pointer-events: none; z-index: 1;
    mix-blend-mode: multiply; opacity: 0.35;
    background-image:
      radial-gradient(circle at 20% 30%, oklch(0.85 0.04 75) 0, transparent 40%),
      radial-gradient(circle at 80% 60%, oklch(0.88 0.03 70) 0, transparent 45%),
      url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' seed='4'/><feColorMatrix values='0 0 0 0 0.15  0 0 0 0 0.1  0 0 0 0 0.05  0 0 0 0.35 0'/></filter><rect width='100%' height='100%' filter='url(%23n)' opacity='0.55'/></svg>");
    background-size: 100% 100%, 100% 100%, 240px 240px;
  }
  .paper-edge {
    position: fixed; inset: 0; pointer-events: none; z-index: 2;
    box-shadow:
      inset 0 0 80px oklch(0.30 0.06 50 / 0.12),
      inset 0 0 240px oklch(0.30 0.06 50 / 0.08);
  }

  .petdex > * { position: relative; z-index: 3; }

  /* ░░ RULES & ORNAMENTS ░░ */
  .rule { width: 100%; margin: 0.8rem 0; }
  .rule-double {
    border-top: 1px solid var(--rule);
    border-bottom: 1px solid var(--rule);
    height: 4px;
  }
  .rule-thin { height: 1px; background: var(--rule); }
  .rule-leaf, .rule-ornament {
    display: flex; align-items: center; gap: 1rem;
    margin: 3rem 0;
  }
  .rule-leaf::before, .rule-leaf::after,
  .rule-ornament::before, .rule-ornament::after {
    content: ""; flex: 1; height: 1px; background: var(--rule);
  }
  .rule-leaf-glyph, .rule-ornament-glyph {
    color: var(--oxblood);
    font-size: 1.4rem;
    font-family: var(--font-display);
    font-variation-settings: "opsz" 144;
  }
  .rule-ornament-glyph { font-style: italic; font-size: 2rem; }

  /* ░░ MASTHEAD ░░ */
  .masthead {
    padding: 2.4rem clamp(1.4rem, 5vw, 5rem) 1.6rem;
    max-width: 1280px;
    margin: 0 auto;
  }
  .masthead-row {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 0.7rem 0;
    font-size: 0.78rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-soft);
  }
  .meta-tag.center { justify-self: center; }
  .meta-tag.right { justify-self: end; }
  .meta-tag.mono { font-family: var(--font-mono); letter-spacing: 0.04em; text-transform: none; }
  .meta-tag a { color: var(--oxblood); text-decoration: none; border-bottom: 1px dotted var(--oxblood); }

  .wordmark {
    text-align: center;
    line-height: 0.86;
    margin: 1.2rem 0 0.5rem;
    font-family: var(--font-display);
    font-weight: 400;
    color: var(--ink);
  }
  .wm-the {
    display: block;
    font-style: italic;
    font-size: clamp(1.6rem, 3.4vw, 2.8rem);
    font-variation-settings: "opsz" 60, "SOFT" 100, "WONK" 1;
    color: var(--ink-soft);
    letter-spacing: 0.04em;
  }
  .wm-main {
    display: block;
    font-size: clamp(5rem, 17vw, 16rem);
    font-weight: 900;
    font-variation-settings: "opsz" 144, "SOFT" 30, "WONK" 1;
    letter-spacing: -0.02em;
    color: var(--ink);
    /* gentle ink-press */
    text-shadow: 0 0 0.5px var(--ink), 0 0.4px 0 oklch(0.30 0.05 50 / 0.4);
  }
  .mounted .wm-main { animation: settle 1100ms cubic-bezier(.16,.84,.32,1) both; }
  @keyframes settle {
    0%   { opacity: 0; transform: translateY(20px) scaleY(1.04); letter-spacing: 0.05em; }
    60%  { opacity: 1; letter-spacing: -0.025em; }
    100% { opacity: 1; transform: translateY(0); letter-spacing: -0.02em; }
  }

  .tagline {
    text-align: center;
    font-size: clamp(0.95rem, 1.4vw, 1.15rem);
    color: var(--ink-soft);
    margin: 0.4rem auto 1.4rem;
  }
  .tagline em {
    font-style: italic;
    color: var(--ink);
    font-variation-settings: "opsz" 24, "SOFT" 100;
  }
  .ornament {
    color: var(--oxblood);
    font-size: 1.1em;
    margin: 0 0.5em;
  }

  .caps {
    font-variant-caps: all-small-caps;
    letter-spacing: 0.08em;
  }
  .small { font-size: 0.78rem; }
  .mono { font-family: var(--font-mono); }

  /* ░░ ESTABLISHING PLATE ░░ */
  .plate-establishing {
    max-width: 1280px;
    margin: 2rem auto 3rem;
    padding: 0 clamp(1.4rem, 5vw, 5rem);
    display: grid;
    grid-template-columns: 1fr minmax(0, 2fr) 1fr;
    gap: clamp(1.2rem, 2.5vw, 2.8rem);
    align-items: start;
  }
  @media (max-width: 980px) {
    .plate-establishing {
      grid-template-columns: 1fr;
    }
  }

  .margin-left, .margin-right {
    font-size: 0.9rem;
    color: var(--ink-soft);
    padding-top: 4rem;
  }
  .margin-note {
    font-style: italic;
    margin: 0 0 1.3rem;
    line-height: 1.5;
    padding-left: 0.8rem;
    border-left: 1px solid var(--ink-faint);
  }
  .margin-num {
    display: inline-block;
    font-weight: 700;
    color: var(--oxblood);
    margin-right: 0.35em;
    font-style: normal;
  }

  .plate-figure {
    position: relative;
    text-align: center;
  }
  .plate-stamp {
    position: absolute;
    top: -0.5rem; left: 50%;
    transform: translateX(-50%);
    background: var(--paper);
    padding: 0 1rem;
    z-index: 4;
  }
  .plate-label {
    display: block;
    font-variant-caps: all-small-caps;
    letter-spacing: 0.18em;
    font-size: 0.72rem;
    color: var(--ink-soft);
  }
  .plate-roman {
    display: block;
    font-family: var(--font-display);
    font-size: 2.6rem;
    font-variation-settings: "opsz" 144, "WONK" 1;
    line-height: 1;
    color: var(--ink);
  }
  .vitrine {
    position: relative;
    border: 1px solid var(--rule);
    padding: 3rem 2rem 2rem;
    background:
      linear-gradient(180deg, oklch(0.97 0.018 80) 0%, oklch(0.92 0.028 78) 100%);
    box-shadow:
      0 1px 0 oklch(1 0 0 / 0.6) inset,
      0 -1px 0 oklch(0.30 0.04 50 / 0.15) inset,
      0 22px 38px -28px oklch(0.30 0.04 50 / 0.5);
  }
  .vitrine-glass {
    position: absolute; inset: 0;
    background:
      linear-gradient(115deg, transparent 40%, oklch(1 0 0 / 0.25) 50%, transparent 60%);
    pointer-events: none;
  }
  .vitrine-shelf {
    position: absolute; left: 1rem; right: 1rem; bottom: 1.2rem;
    height: 4px;
    background: var(--ink);
    box-shadow: 0 3px 0 oklch(0.30 0.04 50 / 0.25);
  }
  .plate-img {
    width: 100%; height: auto;
    max-height: 380px;
    object-fit: contain;
    filter: drop-shadow(0 14px 18px oklch(0.30 0.04 50 / 0.22));
  }
  .float { animation: floatY 6s ease-in-out infinite; }
  @keyframes floatY {
    0%, 100% { transform: translateY(0); }
    50%      { transform: translateY(-8px); }
  }
  figcaption {
    margin-top: 1rem;
    font-style: italic;
    font-size: 0.85rem;
    color: var(--ink-soft);
    max-width: 36ch;
    margin-inline: auto;
  }

  /* ░░ INSTALL CARD ░░ */
  .install-card {
    background: oklch(0.99 0.012 80);
    border: 1px solid var(--ink);
    padding: 1.2rem 1.2rem 1rem;
    margin-top: 4rem;
    position: relative;
    box-shadow: 4px 4px 0 var(--ink);
  }
  .install-card::before {
    content: ""; position: absolute;
    top: -8px; left: -8px; right: 8px; bottom: 8px;
    border: 1px solid var(--ink-faint);
    z-index: -1;
    pointer-events: none;
  }
  .ic-head {
    display: flex; justify-content: space-between; align-items: baseline;
    font-size: 0.85rem;
    border-bottom: 1px dashed var(--ink-faint);
    padding-bottom: 0.55rem;
    margin-bottom: 0.7rem;
  }
  .ic-sigil { color: var(--oxblood); font-family: var(--font-display); }
  .ic-desc {
    font-style: italic;
    font-size: 0.9rem;
    color: var(--ink-soft);
    margin: 0 0 0.7rem;
  }
  .ic-code {
    background: var(--ink);
    color: oklch(0.96 0.022 80);
    font-family: var(--font-mono);
    font-size: 0.78rem;
    padding: 0.75rem 0.9rem;
    margin: 0;
    line-height: 1.7;
    overflow-x: auto;
    border: 1px solid oklch(0.40 0.06 50);
  }
  .ic-line { display: block; }
  .ic-prompt { color: oklch(0.70 0.15 40); margin-right: 0.6em; }
  .ic-cmd { color: oklch(0.94 0.02 80); }
  .ic-actions {
    display: flex; gap: 0.6rem; margin-top: 0.75rem;
    flex-wrap: wrap;
  }
  .btn-ink, .btn-ghost {
    font-family: var(--font-body);
    font-size: 0.82rem;
    font-variant-caps: all-small-caps;
    letter-spacing: 0.08em;
    padding: 0.5rem 0.9rem;
    border: 1px solid var(--ink);
    background: var(--ink);
    color: var(--paper);
    cursor: pointer;
    transition: transform 120ms ease, background 120ms ease, color 120ms ease;
    text-decoration: none;
    display: inline-block;
  }
  .btn-ink:hover { background: var(--oxblood); border-color: var(--oxblood); transform: translate(-1px, -1px); }
  .btn-ghost {
    background: transparent;
    color: var(--ink);
  }
  .btn-ghost:hover { background: var(--ink); color: var(--paper); transform: translate(-1px, -1px); }

  /* ░░ ABSTRACT ░░ */
  .abstract {
    max-width: 980px;
    margin: 4rem auto;
    padding: 0 clamp(1.4rem, 5vw, 5rem);
    text-align: center;
  }
  .section-title {
    font-family: var(--font-display);
    font-style: italic;
    font-weight: 400;
    font-size: clamp(2rem, 4vw, 3.4rem);
    font-variation-settings: "opsz" 96, "SOFT" 100, "WONK" 1;
    letter-spacing: -0.01em;
    margin: 0 0 1.2rem;
    color: var(--ink);
  }
  .abstract-cols {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2.2rem;
    text-align: left;
    margin-top: 1.5rem;
  }
  @media (max-width: 760px) {
    .abstract-cols { grid-template-columns: 1fr; }
  }
  .ab-col {
    font-size: 1.05rem;
    line-height: 1.65;
    color: var(--ink);
    font-variation-settings: "opsz" 18, "SOFT" 70;
    hyphens: auto;
    text-align: justify;
  }
  .drop-cap::first-letter {
    font-family: var(--font-display);
    font-size: 4.2em;
    font-weight: 700;
    line-height: 0.84;
    float: left;
    padding: 0.15em 0.12em 0 0;
    color: var(--oxblood);
    font-variation-settings: "opsz" 144, "WONK" 1;
  }

  /* ░░ TABLE OF CONTENTS ░░ */
  .toc {
    max-width: 880px;
    margin: 4rem auto;
    padding: 2rem clamp(1.4rem, 4vw, 3rem);
    border: 1px solid var(--rule);
    background: oklch(0.97 0.016 80 / 0.55);
  }
  .toc-head {
    display: flex; justify-content: space-between; align-items: baseline;
    font-size: 0.85rem;
    margin-bottom: 1.2rem;
    color: var(--ink-soft);
  }
  .toc-flourish { font-family: var(--font-display); font-style: italic; color: var(--oxblood); }
  .toc-list { list-style: none; padding: 0; margin: 0; }
  .toc-item {
    display: grid;
    grid-template-columns: 3rem 1fr 4rem;
    gap: 1rem;
    align-items: baseline;
    padding: 0.55rem 0;
    border-top: 1px dotted var(--ink-faint);
  }
  .toc-item:last-child { border-bottom: 1px dotted var(--ink-faint); }
  .toc-num {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--oxblood);
    font-weight: 600;
  }
  .toc-name {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: baseline;
    gap: 0.4rem;
    text-decoration: none;
    color: var(--ink);
  }
  .toc-latin {
    font-style: italic;
    font-size: 1.1rem;
    font-variation-settings: "opsz" 36, "SOFT" 100;
  }
  .toc-common {
    font-variant-caps: all-small-caps;
    letter-spacing: 0.1em;
    color: var(--ink-soft);
    font-size: 0.95rem;
  }
  .toc-dots {
    border-bottom: 1px dotted var(--ink-faint);
    height: 0.7rem;
  }
  .toc-page {
    font-family: var(--font-mono);
    font-size: 0.78rem;
    text-align: right;
    color: var(--ink-soft);
  }
  .toc-name:hover .toc-latin { color: var(--oxblood); }

  /* ░░ SPECIMEN ENTRIES ░░ */
  .specimen {
    max-width: 1180px;
    margin: 4.5rem auto;
    padding: 0 clamp(1.4rem, 5vw, 5rem);
    scroll-margin-top: 3rem;
  }
  .tint-ochre   { --tint: var(--ochre); }
  .tint-ember   { --tint: var(--ember); }
  .tint-verdigris { --tint: var(--verdigris); }

  .sp-head {
    display: grid;
    grid-template-columns: auto 1fr auto;
    gap: 1.4rem;
    align-items: start;
    padding-bottom: 1.4rem;
    border-bottom: 1px solid var(--rule);
  }
  .sp-plate {
    border: 1px solid var(--ink);
    padding: 0.6rem 0.9rem;
    text-align: center;
    min-width: 4.4rem;
  }
  .sp-plate-l {
    display: block;
    font-variant-caps: all-small-caps;
    letter-spacing: 0.14em;
    font-size: 0.66rem;
    color: var(--ink-soft);
  }
  .sp-plate-n {
    display: block;
    font-family: var(--font-display);
    font-variation-settings: "opsz" 144, "WONK" 1;
    font-size: 1.8rem;
    line-height: 1;
  }
  .sp-titleblock { padding-top: 0.2rem; }
  .sp-number {
    font-variant-caps: all-small-caps;
    letter-spacing: 0.14em;
    font-size: 0.78rem;
    color: var(--ink-soft);
    margin: 0 0 0.35rem;
  }
  .sp-latin {
    font-family: var(--font-display);
    font-weight: 400;
    font-size: clamp(2rem, 4.4vw, 3.6rem);
    font-variation-settings: "opsz" 144, "SOFT" 100, "WONK" 1;
    line-height: 1;
    margin: 0 0 0.55rem;
    color: var(--ink);
  }
  .sp-latin em { color: var(--oxblood); }
  .sp-common {
    font-size: 1rem;
    color: var(--ink-soft);
    margin: 0;
  }
  .sp-epithet { font-style: italic; color: var(--ink); }

  /* circular stamp */
  .sp-stamp {
    position: relative;
    width: 96px; height: 96px;
    flex-shrink: 0;
    color: var(--tint);
  }
  .stamp-ring {
    position: absolute; inset: 0;
    border-radius: 50%;
    border: 1.5px dashed currentColor;
  }
  .stamp-ring::before {
    content: ""; position: absolute; inset: 6px;
    border-radius: 50%;
    border: 1px solid currentColor;
  }
  .stamp-text {
    position: absolute; inset: 0;
    font-family: var(--font-mono);
    font-size: 9px;
    letter-spacing: 0.08em;
    opacity: 0;     /* the curved text path is decorative; ring carries the look */
  }
  .stamp-core {
    position: absolute; inset: 0;
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    font-family: var(--font-display);
    font-size: 0.7rem;
    line-height: 1.2;
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
  .stamp-core strong {
    font-size: 1.4rem;
    font-weight: 800;
    font-variation-settings: "opsz" 144;
    letter-spacing: 0;
  }
  .sp-stamp { animation: stampIn 600ms ease-out both; transform-origin: center; }
  @keyframes stampIn {
    from { opacity: 0; transform: rotate(-12deg) scale(0.6); }
    to   { opacity: 1; transform: rotate(-6deg) scale(1); }
  }

  /* body */
  .sp-body {
    display: grid;
    grid-template-columns: 0.9fr 1fr;
    gap: clamp(1.6rem, 4vw, 3.2rem);
    margin-top: 2rem;
    align-items: start;
  }
  @media (max-width: 860px) {
    .sp-body { grid-template-columns: 1fr; }
    .sp-head { grid-template-columns: auto 1fr; }
    .sp-stamp { display: none; }
  }
  .sp-figure { margin: 0; }
  .sp-illus-frame {
    position: relative;
    border: 1px solid var(--ink);
    padding: 1.4rem;
    background:
      radial-gradient(circle at 30% 25%, oklch(0.98 0.02 80), oklch(0.92 0.04 78));
    box-shadow:
      inset 0 0 0 4px var(--paper),
      inset 0 0 0 5px var(--rule),
      8px 8px 0 var(--ink);
  }
  .sp-illus-frame::before {
    content: ""; position: absolute;
    inset: 0;
    background:
      linear-gradient(135deg, transparent 50%, oklch(0.30 0.04 50 / 0.06) 100%);
    pointer-events: none;
  }
  .sp-illus {
    width: 100%; height: auto;
    max-height: 380px;
    object-fit: contain;
    filter: drop-shadow(0 12px 18px oklch(0.30 0.04 50 / 0.25));
  }

  .sp-hook {
    border: 1px solid var(--tint);
    background: oklch(from var(--tint) l c h / 0.08);
    padding: 0.6rem 0.85rem;
    font-size: 0.8rem;
    margin: 0 0 1.2rem;
    display: flex; align-items: baseline; gap: 0.8rem;
  }
  .sp-hook-label {
    font-variant-caps: all-small-caps;
    letter-spacing: 0.14em;
    font-family: var(--font-display);
    color: var(--tint);
    font-weight: 700;
  }
  .sp-hook-value { color: var(--ink); word-break: break-word; }

  .sp-h3 {
    font-family: var(--font-display);
    font-style: italic;
    font-size: 1.15rem;
    font-variation-settings: "opsz" 36, "SOFT" 100;
    margin: 1.5rem 0 0.35rem;
    color: var(--ink);
  }
  .sp-h3::before {
    content: "§ ";
    color: var(--tint);
    font-style: normal;
  }
  .sp-text {
    margin: 0;
    font-size: 1.02rem;
    line-height: 1.6;
  }
  .sp-dl {
    margin: 0.4rem 0 0;
    border-top: 1px solid var(--rule);
  }
  .sp-dl-row {
    display: grid;
    grid-template-columns: 1fr 2fr;
    border-bottom: 1px solid var(--rule);
    padding: 0.45rem 0;
    font-size: 0.92rem;
  }
  .sp-dl-row dt {
    font-variant-caps: all-small-caps;
    letter-spacing: 0.1em;
    color: var(--ink-soft);
    margin: 0;
  }
  .sp-dl-row dd {
    margin: 0;
    font-style: italic;
  }
  .sp-margin {
    margin: 1.5rem 0 0;
    padding: 0.8rem 1rem;
    border-left: 3px solid var(--tint);
    font-size: 0.9rem;
    color: var(--ink-soft);
    background: oklch(from var(--tint) l c h / 0.05);
  }

  /* ░░ PROVENANCE ░░ */
  .provenance {
    max-width: 1180px;
    margin: 4rem auto;
    padding: 0 clamp(1.4rem, 5vw, 5rem);
    text-align: center;
  }
  .prov-lede {
    max-width: 50ch;
    margin: 0 auto 2.5rem;
    font-style: italic;
    color: var(--ink-soft);
  }
  .prov-grid {
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 1.4rem;
    text-align: left;
  }
  @media (max-width: 920px) {
    .prov-grid { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 520px) {
    .prov-grid { grid-template-columns: 1fr; }
  }
  .prov-item {
    border-top: 2px solid var(--ink);
    padding: 1rem 0.2rem 0;
    position: relative;
  }
  .prov-roman {
    display: block;
    font-family: var(--font-display);
    font-variation-settings: "opsz" 144;
    font-size: 1.6rem;
    color: var(--oxblood);
    margin-bottom: 0.4rem;
  }
  .prov-h {
    font-family: var(--font-display);
    font-style: italic;
    font-weight: 500;
    font-size: 1.3rem;
    margin: 0 0 0.4rem;
    font-variation-settings: "opsz" 48, "SOFT" 80;
  }
  .prov-t {
    margin: 0;
    font-size: 0.95rem;
    color: var(--ink-soft);
    line-height: 1.55;
  }

  /* ░░ COLOPHON ░░ */
  .colophon {
    max-width: 1180px;
    margin: 4rem auto 2rem;
    padding: 0 clamp(1.4rem, 5vw, 5rem);
  }
  .col-grid {
    display: grid;
    grid-template-columns: 1.4fr 1.4fr 1fr;
    gap: 2rem;
    padding-bottom: 2rem;
  }
  @media (max-width: 760px) {
    .col-grid { grid-template-columns: 1fr; }
  }
  .col-body {
    margin: 0.5rem 0 0;
    font-size: 0.9rem;
    line-height: 1.6;
    color: var(--ink-soft);
  }
  .col-body a { color: var(--oxblood); border-bottom: 1px dotted var(--oxblood); text-decoration: none; }
  .col-body a:hover { background: var(--oxblood); color: var(--paper); border-bottom-color: var(--ink); }
  .col-end {
    text-align: center;
    margin: 2rem 0 0;
    font-family: var(--font-display);
    font-style: italic;
    color: var(--ink-soft);
    letter-spacing: 0.2em;
  }

  /* Generic link inside content */
  .petdex a { color: var(--ink); }
  .petdex a:hover { color: var(--oxblood); }
</style>

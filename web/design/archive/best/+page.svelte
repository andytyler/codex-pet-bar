<script lang="ts">
  import { onMount } from "svelte";
  import PetStrip from "$lib/components/pet-strip.svelte";
  import SpriteCell from "$lib/components/sprite-cell.svelte";
  import {
    Activity,
    Check,
    Copy,
    Download,
    ExternalLink,
    FolderOpen,
    ShieldCheck,
    Star,
    Terminal,
  } from "@lucide/svelte";

  type InstallMethod = "brew" | "source";

  const brewInstallCommand = "brew install --cask andytyler/tap/codex-pet-bar";
  const sourceInstallCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";

  const PET = {
    goblin: "/pets/goblin.webp",
    tock: "/pets/tock.webp",
    boo: "/pets/boo.webp",
    ajt: "/pets/ajt.webp",
    clippy: "/pets/clippy.webp",
    grumble: "/pets/grumble.webp",
  } as const;

  const barRunners = [
    { src: PET.goblin, dir: "right" as const },
    { src: PET.tock, dir: "left" as const },
    { src: PET.boo, dir: "right" as const },
    { src: PET.ajt, dir: "left" as const },
  ];

  const liveStates = [
    {
      label: "listening",
      hook: "SessionStart",
      detail: "Codex is awake",
      benefit: "The pet appears when a thread starts.",
      event: "~/.codex/events/session.json",
      img: "/states/listening-ear.png",
      tone: "blue",
    },
    {
      label: "running",
      hook: "PreToolUse",
      detail: "tools are moving",
      benefit: "Tool activity gets a visible pulse.",
      event: "tool: shell / edit / search",
      img: "/states/running.png",
      tone: "amber",
    },
    {
      label: "approval",
      hook: "PermissionRequest",
      detail: "your call",
      benefit: "Approvals stop hiding in the terminal.",
      event: "awaiting local permission",
      img: "/states/waiting.png",
      tone: "violet",
    },
    {
      label: "complete",
      hook: "PostToolUse",
      detail: "thread settled",
      benefit: "Done gets a small finish signal.",
      event: "last tool settled",
      img: "/states/waving.png",
      tone: "green",
    },
  ];

  const moments = [
    {
      hook: "PermissionRequest",
      title: "A pause becomes a character.",
      body: "When Codex needs approval, the menu bar changes from ambient to deliberate. You can see that the next move is yours.",
      img: "/artwork/moments/approval-rock.png",
      tone: "blue",
    },
    {
      hook: "PreToolUse",
      title: "Tool runs get a pulse.",
      body: "Edits, searches, and shell commands stop feeling like invisible waiting. The pet moves while the agent moves.",
      img: "/artwork/moments/running-flame.png",
      tone: "amber",
    },
    {
      hook: "PostToolUse",
      title: "Done gets a finish line.",
      body: "Completed work gets a small ending beat, so long-running threads do not just disappear back into the terminal.",
      img: "/artwork/moments/completed-ajt.png",
      tone: "green",
    },
  ];

  const cast = [
    { name: "Goblin", file: "goblin.pet", src: PET.goblin, state: "runningRight" as const },
    { name: "Tock", file: "tock.pet", src: PET.tock, state: "idle" as const },
    { name: "Boo", file: "boo.pet", src: PET.boo, state: "waiting" as const },
    { name: "AJT", file: "ajt.pet", src: PET.ajt, state: "waving" as const },
    { name: "Clippy", file: "clippy.pet", src: PET.clippy, state: "review" as const },
    { name: "Grumble", file: "grumble.pet", src: PET.grumble, state: "failed" as const },
  ];

  const principles = [
    {
      title: "Local first",
      body: "Hooks read local Codex activity and write small status updates under ~/.codex.",
    },
    {
      title: "No cloud account",
      body: "The app is a menu-bar utility, not a hosted service or telemetry pipe.",
    },
    {
      title: "Hackable by design",
      body: "Pets are filesystem packages. Inspect them, fork them, or replace them.",
    },
  ];

  let selectedInstallMethod = $state<InstallMethod>("brew");
  let copiedInstallCommand = $state(false);
  let copyResetTimeout: ReturnType<typeof setTimeout> | undefined;
  let activeState = $state(0);
  let clock = $state("--:--");
  let mounted = $state(false);

  const live = $derived(liveStates[activeState]);
  const selectedInstallCommand = $derived(selectedInstallMethod === "brew" ? brewInstallCommand : sourceInstallCommand);
  const selectedInstallLines = $derived(selectedInstallCommand.split("\n"));

  const tickClock = () => {
    const date = new Date();
    const hours = date.getHours();
    const minutes = date.getMinutes();
    clock = `${((hours + 11) % 12) + 1}:${String(minutes).padStart(2, "0")} ${hours < 12 ? "AM" : "PM"}`;
  };

  const writeClipboardText = async (text: string) => {
    if (typeof document === "undefined") return false;

    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        // Fall through to the textarea fallback for browsers that block clipboard writes.
      }
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    textarea.style.pointerEvents = "none";

    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();

    return copied;
  };

  const copyInstallCommand = async () => {
    copiedInstallCommand = await writeClipboardText(selectedInstallCommand);

    if (copyResetTimeout) {
      clearTimeout(copyResetTimeout);
    }

    if (copiedInstallCommand) {
      copyResetTimeout = setTimeout(() => {
        copiedInstallCommand = false;
      }, 1800);
    }
  };

  onMount(() => {
    mounted = true;
    tickClock();

    const clockInterval = setInterval(tickClock, 30_000);
    const stateInterval = setInterval(() => {
      activeState = (activeState + 1) % liveStates.length;
    }, 2400);

    return () => {
      clearInterval(clockInterval);
      clearInterval(stateInterval);
      if (copyResetTimeout) clearTimeout(copyResetTimeout);
    };
  });
</script>

<svelte:head>
  <title>Codex Pet Bar - Codex, with company</title>
  <meta
    name="description"
    content="Codex Pet Bar is a macOS menu-bar companion that turns local Codex hooks, approvals, tool runs, and completions into tiny pet states." />
  <meta property="og:title" content="Codex Pet Bar" />
  <meta property="og:description" content="Tiny menu-bar pets for local Codex activity." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-clean-hero.png" />
  <meta name="twitter:title" content="Codex Pet Bar" />
  <meta name="twitter:description" content="Tiny menu-bar pets for local Codex activity." />
</svelte:head>

<div class="best-page" class:mounted>
  <nav class="system-bar" aria-label="Primary">
    <a class="brand" href="#top" aria-label="Codex Pet Bar home">
      <img src="/artwork/codex-pet-bar-icon.png" alt="" />
      <span>Codex Pet Bar</span>
    </a>

    <div class="system-menu" aria-label="Page sections">
      <a href="#moments">Moments</a>
      <a href="#pets">Pets</a>
      <a href="#install">Install</a>
    </div>

    <div class="system-right">
      <span class={`status-pill tone-${live.tone}`}>
        <span></span>
        {live.label}
      </span>
      <span class="clock">{clock}</span>
      <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer" aria-label="Open GitHub repository">
        <ExternalLink size={16} aria-hidden="true" />
      </a>
    </div>
  </nav>

  <main id="top">
    <section class="hero-scene" aria-labelledby="hero-title">
      <aside class="sticky-note" aria-label="Product note">
        <p>keep it local.</p>
        <p>keep it visible.</p>
        <p>make the agent feel present.</p>
      </aside>

      <section class="readme-window">
        <header class="titlebar">
          <div class="window-buttons" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
          </div>
          <div class="title-lines" aria-hidden="true"></div>
          <strong>ReadMe - Codex Pet Bar.app</strong>
          <div class="title-lines" aria-hidden="true"></div>
        </header>

        <PetStrip pets={barRunners} height={30} label="Pets running across the Codex Pet Bar window" />

        <div class="hero-window-body">
          <div class="hero-copy">
            <p class="pretitle">macOS menu-bar companion for Codex</p>
            <h1 id="hero-title">
              <span>Codex,</span>
              <em>with</em>
              <em class="company-line">company.</em>
            </h1>
            <p class="lede">
              Tiny pets live where your agent already reports status. They listen to local Codex hooks, react to approvals,
              move during tool runs, and settle when the thread is done.
            </p>

            <div class="hero-actions">
              <a class="button primary" href="#install">
                <Download size={18} aria-hidden="true" />
                Install with Homebrew
              </a>
              <a class="button secondary" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">
                <Star size={18} aria-hidden="true" />
                Star on GitHub
              </a>
            </div>

            <p class="hero-trust-line"><span></span>Runs locally. No cloud. Your code stays yours.</p>
          </div>

          <figure class="hero-art">
            <img src="/artwork/codex-pet-bar-hero-trans.png" alt="A lineup of Codex Pet Bar pets sitting on a menu bar shelf." />
            <figcaption>Representative specimens, shown at rest.</figcaption>
          </figure>

          <div class="hero-proof-dock" aria-label="Core qualities">
            {#each principles as principle}
              <article>
                <h2>{principle.title}</h2>
                <p>{principle.body}</p>
              </article>
            {/each}
          </div>
        </div>
      </section>

      <aside class="live-card" aria-label="Current Codex Pet Bar state">
        <div class="inspector-title">
          <span>Hook Inspector</span>
          <b>live</b>
        </div>
        <div class="mini-menubar">
          <span>codex</span>
          <span class={`mini-state tone-${live.tone}`}>
            <span></span>
            {live.label}
          </span>
          <img src={live.img} alt="" />
          <span>{clock}</span>
        </div>
        <div class={`live-preview tone-${live.tone}`}>
          <span>current hook</span>
          <img src={live.img} alt="" />
          <strong>{live.hook}</strong>
          <p>{live.benefit}</p>
          <code>{live.event}</code>
        </div>
        <div class="state-stack">
          {#each liveStates as state, i}
            <button
              type="button"
              class={`tone-${state.tone}`}
              class:active={i === activeState}
              onclick={() => (activeState = i)}
              aria-label={`Show ${state.hook} state`}>
              <img src={state.img} alt="" />
              <span>
                <strong>{state.hook}</strong>
                <small>{state.detail}</small>
              </span>
            </button>
          {/each}
        </div>
        <a class="quick-install" href="#install">
          <Terminal size={16} aria-hidden="true" />
          <span>{brewInstallCommand}</span>
        </a>
      </aside>
    </section>

    <section class="moments" id="moments" aria-labelledby="moments-title">
      <header class="section-head">
        <p>hook reactions</p>
        <h2 id="moments-title">The agent lifecycle, made visible.</h2>
      </header>

      <div class="moment-list">
        {#each moments as moment}
          <article class={`moment tone-${moment.tone}`}>
            <img src={moment.img} alt="" />
            <div>
              <p>{moment.hook}</p>
              <h3>{moment.title}</h3>
              <span>{moment.body}</span>
            </div>
          </article>
        {/each}
      </div>
    </section>

    <section class="pets-folder" id="pets" aria-labelledby="pets-title">
      <div class="folder-copy">
        <p class="pretitle">~/.codex/pets</p>
        <h2 id="pets-title">A real pets folder, not just campaign art.</h2>
        <p>
          Each pet is a package on disk. The page uses the same sprite atlas idea the app ships with, so the marketing
          surface still feels like the product.
        </p>
      </div>

      <div class="folder-window">
        <header class="titlebar compact">
          <div class="window-buttons" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
          </div>
          <strong>Pets - 6 items</strong>
        </header>
        <div class="folder-toolbar">
          <span>Icon</span>
          <span>List</span>
          <b>~/.codex/pets/</b>
        </div>
        <div class="cast-grid">
          {#each cast as pet, i}
            <article>
              <SpriteCell src={pet.src} state={pet.state} size={58} phase={i / cast.length} />
              <strong>{pet.name}</strong>
              <span>{pet.file}</span>
            </article>
          {/each}
        </div>
      </div>
    </section>

    <section class="install-section" id="install" aria-labelledby="install-title">
      <div class="install-copy">
        <p class="pretitle">installation</p>
        <h2 id="install-title">Three lines, then look up.</h2>
        <p>
          Use Homebrew or run the local installer. The app stays local, and the hooks write small state updates below
          <code>~/.codex</code>.
        </p>
        <ul>
          <li><ShieldCheck size={18} aria-hidden="true" />No account or hosted service.</li>
          <li><Activity size={18} aria-hidden="true" />Status is driven by local hook metadata.</li>
          <li><FolderOpen size={18} aria-hidden="true" />Custom pets live on disk.</li>
        </ul>
      </div>

      <div class="terminal-window" data-testid="best-install-code-box">
        <header>
          <Terminal size={18} aria-hidden="true" />
          <span>terminal - install.sh</span>
          <button type="button" onclick={copyInstallCommand} aria-label={copiedInstallCommand ? "Install command copied" : "Copy install command"}>
            {#if copiedInstallCommand}
              <Check size={17} aria-hidden="true" />
              Copied
            {:else}
              <Copy size={17} aria-hidden="true" />
              Copy
            {/if}
          </button>
        </header>

        <div class="install-tabs" data-testid="best-install-code-tabs" role="tablist" aria-label="Install method">
          <button
            type="button"
            role="tab"
            class:active={selectedInstallMethod === "brew"}
            aria-selected={selectedInstallMethod === "brew"}
            onclick={() => (selectedInstallMethod = "brew")}>
            Homebrew
          </button>
          <button
            type="button"
            role="tab"
            class:active={selectedInstallMethod === "source"}
            aria-selected={selectedInstallMethod === "source"}
            onclick={() => (selectedInstallMethod = "source")}>
            Source
          </button>
        </div>

        <pre data-testid="best-install-code-panel"><code>{#each selectedInstallLines as line}<span><b>$</b>{line}</span>{/each}</code></pre>
      </div>
    </section>
  </main>

  <footer>
    <span>Codex Pet Bar is open source under the MIT License.</span>
    <div>
      <a href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">GitHub</a>
      <a href="#top">Back to top</a>
    </div>
  </footer>
</div>

<style>
  .best-page {
    --ink: #17130e;
    --paper: #f7f3e8;
    --paper-2: #fffdf6;
    --line: #252018;
    --muted: #6c6258;
    --blue: #0866e8;
    --cyan: #51e8ff;
    --green: #27895b;
    --amber: #f36b24;
    --violet: #7157e8;
    --shadow-hard: 8px 8px 0 rgba(23, 19, 14, 0.92);
    --shadow-soft: 0 26px 80px rgba(23, 19, 14, 0.16);
    min-height: 100svh;
    overflow-x: hidden;
    background:
      radial-gradient(circle at 18% 18%, rgba(8, 102, 232, 0.13), transparent 28%),
      radial-gradient(circle at 86% 10%, rgba(243, 107, 36, 0.13), transparent 24%),
      linear-gradient(180deg, #f8f5ed 0%, #f2ecdd 62%, #f6f7fb 100%);
    color: var(--ink);
    font-family: "Inter Variable", Inter, ui-sans-serif, system-ui, sans-serif;
  }

  .best-page::before {
    position: fixed;
    inset: 0;
    z-index: 0;
    pointer-events: none;
    background-image:
      linear-gradient(rgba(23, 19, 14, 0.035) 1px, transparent 1px),
      linear-gradient(90deg, rgba(23, 19, 14, 0.026) 1px, transparent 1px);
    background-size: 18px 18px;
    mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.52), transparent 80%);
    content: "";
  }

  .best-page a {
    text-decoration: none;
  }

  main,
  footer,
  .system-bar {
    position: relative;
    z-index: 1;
  }

  .system-bar {
    position: sticky;
    top: 0;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
    align-items: center;
    min-height: 38px;
    border-bottom: 2px solid var(--line);
    background: rgba(255, 253, 246, 0.94);
    padding: 0 18px;
    backdrop-filter: blur(16px);
  }

  .brand,
  .system-menu,
  .system-right,
  .status-pill,
  .mini-state {
    display: flex;
    align-items: center;
  }

  .brand {
    gap: 9px;
    min-width: 0;
    color: var(--ink);
    font-weight: 900;
  }

  .brand img {
    width: 27px;
    height: 27px;
    border: 1.5px solid var(--line);
    border-radius: 6px;
    object-fit: cover;
    background: #fff;
  }

  .system-menu {
    justify-content: center;
    gap: 6px;
  }

  .system-menu a {
    border-radius: 6px;
    color: var(--ink);
    font-size: 0.86rem;
    font-weight: 800;
    padding: 7px 11px;
  }

  .system-menu a:hover {
    background: var(--ink);
    color: #fff;
  }

  .system-right {
    justify-content: flex-end;
    gap: 12px;
    min-width: 0;
  }

  .status-pill {
    gap: 7px;
    border: 1.5px solid var(--line);
    border-radius: 999px;
    background: #fff;
    color: var(--ink);
    padding: 4px 9px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.76rem;
    font-weight: 800;
  }

  .status-pill span,
  .mini-state span {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--cyan);
    box-shadow: 0 0 12px var(--cyan);
  }

  .status-pill.tone-amber > span,
  .mini-state.tone-amber > span {
    background: #ffb14a;
    box-shadow: 0 0 12px #ffb14a;
  }

  .status-pill.tone-violet > span,
  .mini-state.tone-violet > span {
    background: #b19fff;
    box-shadow: 0 0 12px #b19fff;
  }

  .status-pill.tone-green > span,
  .mini-state.tone-green > span {
    background: #75e7a4;
    box-shadow: 0 0 12px #75e7a4;
  }

  .clock {
    color: #443d35;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
    font-weight: 800;
    white-space: nowrap;
  }

  .system-right a {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border: 1.5px solid var(--line);
    border-radius: 6px;
    background: var(--ink);
    color: #fff;
  }

  .hero-scene {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 810px) minmax(360px, 420px);
    gap: 28px;
    align-items: start;
    max-width: 1280px;
    margin: 0 auto;
    padding: 42px 24px 42px;
  }

  .sticky-note {
    position: absolute;
    top: 70px;
    left: clamp(86px, 8vw, 128px);
    z-index: 2;
    width: 172px;
    border: 2px solid rgba(23, 19, 14, 0.42);
    background: #ffe66d;
    box-shadow: 4px 5px 0 rgba(23, 19, 14, 0.24);
    color: #342d23;
    font-family: Georgia, serif;
    font-size: 0.88rem;
    font-style: italic;
    line-height: 1.35;
    padding: 18px 17px;
    transform: rotate(-4deg);
  }

  .sticky-note p {
    margin: 0;
  }

  .readme-window,
  .folder-window,
  .terminal-window {
    border: 2px solid var(--line);
    border-radius: 8px;
    background: var(--paper-2);
    box-shadow: var(--shadow-hard), var(--shadow-soft);
    overflow: hidden;
  }

  .readme-window {
    margin-top: 18px;
    margin-left: 0;
  }

  .titlebar {
    display: grid;
    grid-template-columns: auto minmax(24px, 1fr) auto minmax(24px, 1fr);
    align-items: center;
    gap: 10px;
    min-height: 42px;
    border-bottom: 2px solid var(--line);
    background: #ece7db;
    padding: 0 13px;
    color: var(--ink);
    font-size: 0.82rem;
  }

  .titlebar.compact {
    min-height: 38px;
  }

  .window-buttons {
    display: flex;
    gap: 7px;
  }

  .window-buttons span {
    width: 12px;
    height: 12px;
    border: 1.5px solid var(--line);
    border-radius: 50%;
    background: #ff6257;
  }

  .window-buttons span:nth-child(2) {
    background: #ffcf4d;
  }

  .window-buttons span:nth-child(3) {
    background: #35c768;
  }

  .title-lines {
    height: 11px;
    background: repeating-linear-gradient(180deg, transparent 0 2px, var(--line) 2px 3px);
    opacity: 0.72;
  }

  .hero-window-body {
    position: relative;
    display: grid;
    grid-template-areas:
      "copy art"
      "proof proof";
    grid-template-columns: minmax(410px, 1fr) minmax(260px, 340px);
    gap: 22px 24px;
    padding: 44px 42px 28px;
  }

  .hero-copy {
    position: relative;
    grid-area: copy;
    z-index: 1;
    min-width: 0;
    max-width: 520px;
  }

  .pretitle {
    display: inline-block;
    margin: 0 0 18px;
    background: var(--ink);
    color: #fff;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
    font-weight: 800;
    letter-spacing: 0.02em;
    padding: 8px 11px;
  }

  h1,
  h2,
  h3,
  p {
    text-wrap: pretty;
  }

  h1 {
    display: grid;
    gap: 2px;
    margin: 0;
    font-size: clamp(4rem, 6vw, 6.4rem);
    line-height: 0.9;
    letter-spacing: 0;
  }

  h1 span {
    font-weight: 950;
  }

  h1 em {
    color: #ff6047;
    font-family: Georgia, "Times New Roman", serif;
    font-style: italic;
    font-weight: 700;
  }

  .company-line {
    font-size: 0.82em;
  }

  .lede {
    max-width: 560px;
    margin: 28px 0 0;
    color: #473f36;
    font-size: 1.05rem;
    line-height: 1.72;
  }

  .hero-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 30px;
  }

  .button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 9px;
    min-height: 46px;
    border: 2px solid var(--line);
    border-radius: 7px;
    box-shadow: 3px 3px 0 var(--line);
    font-size: 0.95rem;
    font-weight: 900;
    padding: 0 13px;
  }

  .button.primary {
    background: #ff6047;
    color: #fff;
  }

  .button.secondary {
    background: #fff;
    color: var(--ink);
  }

  .button:hover {
    transform: translate(1px, 1px);
    box-shadow: 2px 2px 0 var(--line);
  }

  .hero-trust-line {
    display: flex;
    gap: 9px;
    align-items: center;
    margin: 20px 0 0;
    color: #433a32;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
    font-weight: 800;
    line-height: 1.45;
  }

  .hero-trust-line span {
    width: 10px;
    height: 10px;
    flex: 0 0 auto;
    border: 1.5px solid var(--line);
    border-radius: 50%;
    background: #45d276;
    box-shadow: 0 0 0 4px rgba(69, 210, 118, 0.16);
  }

  .hero-art {
    grid-area: art;
    align-self: end;
    justify-self: end;
    width: min(100%, 360px);
    margin: 0;
  }

  .hero-art img {
    display: block;
    width: 100%;
    max-height: 390px;
    object-fit: contain;
    filter: drop-shadow(0 22px 26px rgba(23, 19, 14, 0.22));
  }

  .hero-art figcaption {
    margin-top: 12px;
    color: var(--muted);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.76rem;
    font-weight: 800;
    text-align: center;
  }

  .hero-proof-dock {
    grid-area: proof;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0;
    margin: 6px -42px -28px;
    border-top: 2px solid var(--line);
    background: #f0eadf;
  }

  .hero-proof-dock article {
    min-width: 0;
    padding: 17px 22px 19px;
  }

  .hero-proof-dock article + article {
    border-left: 2px dashed rgba(23, 19, 14, 0.25);
  }

  .hero-proof-dock h2 {
    margin: 0;
    font-size: 1rem;
    line-height: 1.1;
  }

  .hero-proof-dock p {
    margin: 7px 0 0;
    color: var(--muted);
    font-size: 0.82rem;
    line-height: 1.42;
  }

  .live-card {
    display: grid;
    gap: 12px;
    margin-top: 76px;
    border: 2px solid var(--line);
    border-radius: 8px;
    background: rgba(255, 253, 246, 0.9);
    box-shadow: var(--shadow-hard), var(--shadow-soft);
    padding: 12px;
  }

  .inspector-title {
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: var(--ink);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.76rem;
    font-weight: 900;
    text-transform: uppercase;
  }

  .inspector-title b {
    border: 1.5px solid var(--line);
    border-radius: 999px;
    background: #dff8e7;
    color: #155336;
    font-size: 0.68rem;
    padding: 3px 8px;
    text-transform: none;
  }

  .mini-menubar {
    display: grid;
    grid-template-columns: auto 1fr auto auto;
    gap: 12px;
    align-items: center;
    min-height: 48px;
    border: 2px solid var(--line);
    border-radius: 8px;
    background: #171b29;
    color: #fff;
    box-shadow: var(--shadow-hard);
    padding: 0 12px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
  }

  .mini-menubar img {
    width: 34px;
    height: 30px;
    object-fit: contain;
  }

  .mini-state {
    justify-self: end;
    gap: 7px;
    color: #eaf2ff;
  }

  .live-preview {
    display: grid;
    grid-template-columns: 76px 1fr;
    column-gap: 12px;
    align-items: center;
    border: 2px solid var(--line);
    border-left-width: 8px;
    border-left-color: var(--cyan);
    border-radius: 8px;
    background: #fffdf6;
    color: var(--ink);
    padding: 12px;
  }

  .live-preview.tone-amber {
    border-left-color: #ffb14a;
  }

  .live-preview.tone-violet {
    border-left-color: #b19fff;
  }

  .live-preview.tone-green {
    border-left-color: #75e7a4;
  }

  .live-preview > span,
  .live-preview strong,
  .live-preview p,
  .live-preview code {
    grid-column: 2;
  }

  .live-preview > span,
  .live-preview code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.69rem;
    font-weight: 900;
  }

  .live-preview > span {
    color: var(--blue);
    text-transform: uppercase;
  }

  .live-preview img {
    grid-column: 1;
    grid-row: span 4;
    width: 68px;
    height: 60px;
    object-fit: contain;
  }

  .live-preview strong {
    margin-top: 3px;
    font-size: 1.03rem;
  }

  .live-preview p {
    margin: 4px 0 0;
    color: var(--muted);
    font-size: 0.82rem;
    line-height: 1.35;
  }

  .live-preview code {
    display: inline-block;
    width: fit-content;
    max-width: 100%;
    margin-top: 8px;
    overflow-wrap: anywhere;
    background: #ede8dc;
    color: #40372e;
  }

  .state-stack {
    display: grid;
    gap: 10px;
  }

  .state-stack button {
    position: relative;
    display: grid;
    grid-template-columns: 42px 1fr;
    gap: 11px;
    align-items: center;
    border: 2px solid var(--line);
    border-radius: 8px;
    background: #fffdf6;
    color: var(--ink);
    cursor: pointer;
    font: inherit;
    padding: 10px;
    text-align: left;
    overflow: hidden;
  }

  .state-stack button::before {
    position: absolute;
    inset: 0 auto 0 0;
    width: 5px;
    background: transparent;
    content: "";
  }

  .state-stack button.active {
    background: #dff1ff;
    box-shadow: 4px 4px 0 var(--line);
  }

  .state-stack button.active::before {
    background: var(--cyan);
  }

  .state-stack button.tone-amber.active::before {
    background: #ffb14a;
  }

  .state-stack button.tone-violet.active::before {
    background: #b19fff;
  }

  .state-stack button.tone-green.active::before {
    background: #75e7a4;
  }

  .state-stack button.active img {
    animation: state-pop 900ms ease-in-out infinite alternate;
  }

  .state-stack img {
    width: 42px;
    height: 32px;
    object-fit: contain;
  }

  .state-stack strong,
  .state-stack small {
    display: block;
  }

  .state-stack strong {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.73rem;
  }

  .state-stack small {
    margin-top: 2px;
    color: var(--muted);
    font-size: 0.76rem;
    font-weight: 700;
  }

  .quick-install {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 9px;
    align-items: center;
    border: 2px solid var(--line);
    border-radius: 8px;
    background: #15120f;
    box-shadow: 4px 4px 0 var(--line);
    color: #fff;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.7rem;
    font-weight: 800;
    padding: 12px;
  }

  .quick-install span {
    min-width: 0;
    line-height: 1.35;
  }

  .moments,
  .pets-folder,
  .install-section,
  footer {
    max-width: 1160px;
    margin: 0 auto;
    padding-right: 24px;
    padding-left: 24px;
  }

  .section-head {
    display: grid;
    grid-template-columns: minmax(0, 0.45fr) minmax(0, 1fr);
    gap: 24px;
    align-items: end;
    border-top: 2px solid var(--line);
    padding-top: 36px;
  }

  .section-head p {
    margin: 0;
    color: #ff6047;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
    font-weight: 900;
    text-transform: uppercase;
  }

  .section-head h2,
  .folder-copy h2,
  .install-copy h2 {
    margin: 0;
    font-size: clamp(2.4rem, 5vw, 5rem);
    line-height: 0.98;
    letter-spacing: 0;
  }

  .moment-list {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 14px;
    padding: 28px 0 86px;
  }

  .moment {
    display: grid;
    grid-template-rows: 250px 1fr;
    border: 2px solid var(--line);
    border-radius: 8px;
    background: #fffdf6;
    box-shadow: 5px 5px 0 var(--line);
    overflow: hidden;
  }

  .moment > img {
    width: 100%;
    height: 250px;
    object-fit: contain;
    padding: 14px;
    background:
      linear-gradient(180deg, rgba(255, 253, 246, 0.25), rgba(255, 253, 246, 0.62)),
      repeating-linear-gradient(0deg, rgba(23, 19, 14, 0.06) 0 1px, transparent 1px 18px);
  }

  .moment.tone-blue > img {
    background-color: #dff1ff;
  }

  .moment.tone-amber > img {
    background-color: #ffe5c7;
  }

  .moment.tone-green > img {
    background-color: #daf8e8;
  }

  .moment div {
    border-top: 2px solid var(--line);
    padding: 20px;
  }

  .moment p {
    margin: 0 0 10px;
    color: var(--blue);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.74rem;
    font-weight: 900;
  }

  .moment h3 {
    margin: 0;
    font-size: 1.32rem;
    line-height: 1.12;
  }

  .moment span {
    display: block;
    margin-top: 12px;
    color: var(--muted);
    line-height: 1.58;
  }

  .pets-folder {
    display: grid;
    grid-template-columns: minmax(0, 0.72fr) minmax(0, 1fr);
    gap: 34px;
    align-items: center;
    padding-bottom: 86px;
  }

  .folder-copy > p:not(.pretitle),
  .install-copy > p {
    margin: 18px 0 0;
    color: var(--muted);
    font-size: 1.02rem;
    line-height: 1.7;
  }

  .folder-toolbar {
    display: flex;
    gap: 8px;
    align-items: center;
    border-bottom: 2px solid var(--line);
    background: #f3eee3;
    padding: 10px 12px;
    font-size: 0.8rem;
  }

  .folder-toolbar span,
  .folder-toolbar b {
    border: 1.5px solid var(--line);
    border-radius: 6px;
    background: #fffdf6;
    padding: 5px 9px;
  }

  .folder-toolbar b {
    margin-left: auto;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .cast-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    background: #e5ddcf;
    gap: 2px;
  }

  .cast-grid article {
    display: grid;
    place-items: center;
    min-height: 150px;
    background: #fffdf6;
    padding: 16px 10px;
    text-align: center;
  }

  .cast-grid strong {
    margin-top: 8px;
    font-size: 0.92rem;
  }

  .cast-grid span {
    color: var(--muted);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.72rem;
  }

  .install-section {
    display: grid;
    grid-template-columns: minmax(0, 0.7fr) minmax(0, 1fr);
    gap: 34px;
    align-items: center;
    border-top: 2px solid var(--line);
    padding-top: 58px;
    padding-bottom: 72px;
  }

  .install-copy ul {
    display: grid;
    gap: 11px;
    margin: 22px 0 0;
    padding: 0;
    list-style: none;
  }

  .install-copy li {
    display: flex;
    gap: 10px;
    align-items: center;
    color: #413a31;
    font-weight: 800;
  }

  .install-copy :global(svg) {
    color: var(--blue);
  }

  code {
    border-radius: 4px;
    background: #fff;
    color: var(--blue);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    padding: 0.08rem 0.28rem;
  }

  .terminal-window {
    background: #15120f;
    color: #fff;
  }

  .terminal-window header {
    display: grid;
    grid-template-columns: auto 1fr auto;
    gap: 10px;
    align-items: center;
    min-height: 52px;
    border-bottom: 2px solid #3a332c;
    background: #24201b;
    padding: 0 13px;
    color: #f7f3e8;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.8rem;
    font-weight: 800;
  }

  .terminal-window header button {
    display: inline-flex;
    gap: 7px;
    align-items: center;
    justify-content: center;
    min-height: 34px;
    border: 1.5px solid #74695d;
    border-radius: 7px;
    background: #fffdf6;
    color: var(--ink);
    cursor: pointer;
    font: inherit;
    padding: 0 10px;
  }

  .install-tabs {
    display: flex;
    gap: 8px;
    border-bottom: 2px solid #3a332c;
    background: #1d1915;
    padding: 10px 12px;
  }

  .install-tabs button {
    min-height: 34px;
    border: 1.5px solid #74695d;
    border-radius: 7px;
    background: transparent;
    color: #f7f3e8;
    cursor: pointer;
    font: inherit;
    font-size: 0.82rem;
    font-weight: 900;
    padding: 0 12px;
  }

  .install-tabs button.active {
    background: #ff6047;
    border-color: #ff6047;
    color: #fff;
  }

  .terminal-window pre {
    margin: 0;
    overflow-x: auto;
    padding: 22px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.92rem;
    line-height: 1.85;
  }

  .terminal-window code {
    display: grid;
    gap: 6px;
    background: transparent;
    color: #fff;
    padding: 0;
  }

  .terminal-window code span {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    gap: 11px;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .terminal-window b {
    color: #7deda6;
  }

  footer {
    display: flex;
    justify-content: space-between;
    gap: 18px;
    border-top: 2px solid var(--line);
    color: var(--muted);
    font-size: 0.9rem;
    padding-top: 26px;
    padding-bottom: 34px;
  }

  footer div {
    display: flex;
    gap: 18px;
    font-weight: 900;
  }

  footer a {
    color: var(--ink);
  }

  @keyframes state-pop {
    from {
      transform: translateY(0);
    }

    to {
      transform: translateY(-3px);
    }
  }

  @media (max-width: 1080px) {
    .hero-scene {
      grid-template-columns: 1fr;
    }

    .sticky-note {
      display: none;
    }

    .readme-window {
      margin-left: 0;
    }

    .live-card {
      margin-top: 0;
    }

    .state-stack {
      grid-template-columns: repeat(4, minmax(0, 1fr));
    }

    .state-stack button {
      grid-template-columns: 1fr;
      text-align: center;
    }

    .state-stack img {
      justify-self: center;
    }
  }

  @media (max-width: 860px) {
    .system-bar {
      grid-template-columns: 1fr auto;
    }

    .system-menu {
      display: none;
    }

    .system-right {
      gap: 8px;
    }

    .status-pill,
    .clock {
      display: none;
    }

    .hero-window-body,
    .moment-list,
    .pets-folder,
    .install-section {
      grid-template-columns: 1fr;
    }

    .section-head {
      grid-template-columns: 1fr;
      gap: 10px;
    }

    .hero-window-body {
      display: grid;
      grid-template-areas:
        "copy"
        "art"
        "proof";
      padding: 34px 24px 28px;
      min-height: 0;
    }

    .hero-art {
      width: 100%;
      max-width: 520px;
      justify-self: center;
    }

    .hero-proof-dock {
      grid-template-columns: 1fr;
      margin: 8px -24px -28px;
    }

    .hero-proof-dock article + article {
      border-top: 2px dashed rgba(23, 19, 14, 0.25);
      border-left: 0;
    }
  }

  @media (max-width: 560px) {
    .system-bar {
      padding: 0 10px;
    }

    .brand span {
      max-width: 178px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .hero-scene,
    .moments,
    .pets-folder,
    .install-section,
    footer {
      padding-right: 14px;
      padding-left: 14px;
    }

    .hero-scene {
      padding-top: 24px;
    }

    .titlebar {
      grid-template-columns: auto 1fr;
    }

    .titlebar .title-lines:last-child {
      display: none;
    }

    h1 {
      font-size: 4rem;
    }

    .pretitle {
      font-size: 0.7rem;
    }

    .lede {
      font-size: 1rem;
    }

    .hero-actions {
      flex-direction: column;
    }

    .button {
      width: 100%;
    }

    .hero-trust-line {
      align-items: flex-start;
    }

    .state-stack {
      grid-template-columns: 1fr 1fr;
    }

    .mini-menubar {
      grid-template-columns: 1fr auto;
    }

    .mini-state,
    .mini-menubar > span:last-child {
      display: none;
    }

    .cast-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .terminal-window header {
      grid-template-columns: auto 1fr;
    }

    .terminal-window header button {
      grid-column: span 2;
    }

    footer {
      flex-direction: column;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .button:hover,
    .state-stack button.active img {
      transform: none;
      animation: none;
    }
  }
</style>

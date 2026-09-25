<script lang="ts">
  import '@fontsource-variable/dm-sans';
  import '@fontsource-variable/fraunces';
  import { base } from '$app/paths';
  import { ArrowDown, ArrowUpRight, Check, Copy, Download } from '@lucide/svelte';
  import SpriteCell from '$lib/components/sprite-cell.svelte';
  import MenuBarDemo from './MenuBarDemo.svelte';

  const repository = 'https://github.com/andytyler/codex-pet-bar';
  const releases = `${repository}/releases/latest`;
  const installCommand = 'brew install --cask andytyler/tap/codex-pet-bar\ncodex-pet-bar';
  const providers = [
    { name: 'Codex', image: 'CodexThreadGlyph.png' },
    { name: 'Claude Code', image: 'ClaudeCodeCrab.svg' },
    { name: 'Cursor', image: 'CursorProviderIconLight.svg' }
  ];
  let copyState = $state<'idle' | 'copied' | 'manual'>('idle');

  async function copyCommand() {
    try {
      await navigator.clipboard.writeText(installCommand);
      copyState = 'copied';
    } catch {
      copyState = 'manual';
    }
  }
</script>

<svelte:head>
  <title>Codex Pet Bar — Your pet. New hangout.</title>
  <meta name="description" content="Your Codex pet, now in your Mac’s menu bar. A little company while you work, with a wave when your coding agents need you. Free and open source." />
  <meta property="og:title" content="Codex Pet Bar — Your pet. New hangout." />
  <meta property="og:description" content="Bring your existing Codex pet to your Mac’s menu bar. A little company while your agents do their thing." />
  <meta property="og:image" content="https://andytyler.github.io/codex-pet-bar/artwork/open-graph/codex-pet-bar-og-clean-hero.png" />
  <meta name="theme-color" content="#fffaf2" />
</svelte:head>

<div class="landing" id="top">
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header page-width">
    <a href="#top" class="brand" aria-label="Codex Pet Bar home">
      <span class="brand-pet" aria-hidden="true"><SpriteCell src={`${base}/pets/goblin.webp`} state="idle" size={37} /></span>
      <span>Codex Pet Bar</span>
    </a>
    <nav aria-label="Main navigation">
      <a class="github-link" href={repository} target="_blank" rel="noreferrer">GitHub <ArrowUpRight size={15} /></a>
      <a class="nav-download" href={releases} target="_blank" rel="noreferrer">Get the app <Download size={16} /></a>
    </nav>
  </header>

  <main id="main">
    <section class="hero" aria-labelledby="hero-title">
      <div class="hero-copy page-width">
        <h1 id="hero-title">Your pet. <em>New hangout.</em></h1>
        <p class="hero-description">Bring your existing Codex pet to your Mac’s menu bar.<br class="desktop-break" /> It hangs out while you work and waves when your agents need you.</p>
        <div class="hero-actions">
          <a class="button primary" href={releases} target="_blank" rel="noreferrer"><Download size={19} strokeWidth={1.9} />Download for Mac</a>
          <a class="homebrew-link" href="#install">or use Homebrew <ArrowDown size={15} /></a>
        </div>
        <p class="compatibility">Free &amp; open source <span aria-hidden="true">·</span> macOS 14+ <span aria-hidden="true">·</span> Apple Silicon</p>
      </div>
      <figure class="hero-art">
        <enhanced:img src="$lib/assets/codex-pets.png" alt="A crowd of colourful Codex pets leaning over a bar, with the green goblin front and centre." sizes="(min-width: 801px) 760px, 100vw" fetchpriority="high" />
      </figure>
    </section>

    <section class="how-it-works page-width" id="how-it-works" aria-labelledby="demo-title">
      <div class="section-heading">
        <p class="eyebrow">Small friend. Useful little signals.</p>
        <h2 id="demo-title">They work. You get a wave.</h2>
        <p>See who’s busy, who needs you, and when it’s time for a breather.</p>
      </div>
      <MenuBarDemo />
      <div class="providers" aria-label="Supported coding agents">
        <span>Keeping an eye on</span>
        {#each providers as provider (provider.name)}
          <span class="provider"><img src={`${base}/landing-assets/${provider.image}`} alt="" width="23" height="23" /><strong>{provider.name}</strong></span>
        {/each}
      </div>
    </section>

    <section class="installation page-width" id="install" aria-labelledby="install-title">
      <div class="install-copy">
        <span class="install-pet" aria-hidden="true"><SpriteCell src={`${base}/pets/goblin.webp`} state="waving" size={65} /></span>
        <h2 id="install-title">Room for one more?</h2>
        <p>Install Pet Bar. Your selected Codex pet comes along.</p>
        <a class="button primary" href={releases} target="_blank" rel="noreferrer"><Download size={18} />Get the Mac app</a>
        <p class="install-hint">Move CodexPetBar.app to Applications, then open it.</p>
      </div>
      <div class="install-options">
        <div class="terminal" aria-label="Homebrew installation commands">
          <div class="terminal-header">
            <span>More of a Terminal person?</span>
            <button type="button" onclick={copyCommand} aria-label="Copy Homebrew install command">
              {#if copyState === 'copied'}<Check size={16} />{:else}<Copy size={16} />{/if}
              {copyState === 'copied' ? 'Copied' : 'Copy'}
            </button>
          </div>
          <pre><code>{installCommand}</code></pre>
        </div>
        <p class="copy-status" role="status" aria-live="polite">{copyState === 'copied' ? 'Copied. Ready to paste into Terminal.' : copyState === 'manual' ? 'Select and copy the command above; clipboard access is unavailable.' : ''}</p>
        <p class="release-note"><strong>Available now: v0.1.2.</strong> The demo previews v0.2, coming soon.</p>
        <details>
          <summary>What’s coming in v0.2?</summary>
          <p>Click your pet for tasks and agent connections. Pet Bar will also ask whether to open at login. Your choice, always.</p>
        </details>
      </div>
    </section>
  </main>

  <footer class="page-width">
    <span>Little pet. Entirely on your Mac.</span>
    <a href={repository} target="_blank" rel="noreferrer">Made for the fun of it. Open source. <ArrowUpRight size={15} /></a>
  </footer>
</div>

<style>
  :global(html) { scroll-behavior: smooth; scroll-padding-top: 30px; }
  :global(body) { margin: 0; }
  .landing { --ink: #22382d; --muted: #667267; --paper: #fffaf2; --orange: #d75631; --line: #dce0d4; color: var(--ink); background: var(--paper); min-height: 100vh; font-family: 'DM Sans Variable', sans-serif; -webkit-font-smoothing: antialiased; }
  .landing :global(*) { box-sizing: border-box; }
  .landing :global(a) { color: inherit; }
  .landing :global(a:focus-visible), .landing :global(button:focus-visible), summary:focus-visible { outline: 3px solid var(--orange); outline-offset: 5px; }
  .landing :global(::selection) { background: #f6d8a4; color: var(--ink); }
  a { text-decoration: none; }
  .page-width { width: min(1120px, calc(100% - 80px)); margin-inline: auto; }
  .skip-link { position: fixed; top: -80px; left: 20px; z-index: 20; padding: 12px 18px; background: var(--ink); border-radius: 8px; }
  .landing .skip-link { color: var(--paper); }
  .skip-link:focus { top: 16px; }
  .site-header { display: flex; justify-content: space-between; align-items: center; gap: 24px; min-height: 78px; }
  .brand { display: flex; gap: 9px; align-items: center; font-size: 20px; font-weight: 750; letter-spacing: -.7px; white-space: nowrap; }
  .brand-pet { width: 37px; height: 42px; }
  nav { display: flex; align-items: center; gap: 28px; font-size: 14px; font-weight: 600; }
  nav a, footer a { display: inline-flex; align-items: center; gap: 6px; }
  nav a:hover, footer a:hover { color: var(--orange); }
  .nav-download { padding: 11px 17px; border: 1px solid #cdd4c6; border-radius: 999px; }
  .hero { padding-top: 14px; text-align: center; }
  .eyebrow { display: flex; justify-content: center; align-items: center; gap: 7px; margin: 0 0 18px; font-size: 13px; font-weight: 650; }
  h1, h2 { font-family: 'Fraunces Variable', Georgia, serif; font-weight: 600; font-variation-settings: 'SOFT' 100, 'WONK' 1; }
  h1 { margin: 0; font-size: clamp(48px, 5.8vw, 74px); line-height: 1.06; letter-spacing: -.065em; }
  h1 em { font-style: normal; color: var(--orange); }
  .hero-description { margin: 18px auto 0; max-width: 620px; font-size: 17px; line-height: 1.5; letter-spacing: -.25px; }
  .hero-actions { display: flex; justify-content: center; align-items: center; gap: 24px; margin-top: 22px; }
  .button { display: inline-flex; justify-content: center; align-items: center; gap: 10px; border-radius: 999px; font-size: 15px; font-weight: 650; min-height: 49px; padding: 13px 24px; transition: transform 160ms ease, background 160ms ease; }
  .landing .primary { color: #fffaf2; background: var(--ink); }
  .primary:hover { background: #365441; transform: translateY(-2px); }
  .homebrew-link { display: inline-flex; align-items: center; gap: 7px; font-size: 14px; text-decoration: underline; text-underline-offset: 4px; }
  .homebrew-link:hover { color: var(--orange); }
  .compatibility { display: flex; justify-content: center; flex-wrap: wrap; gap: 8px; margin: 12px 0 0; color: var(--muted); font-size: 11px; line-height: 1.5; }
  .hero-art { position: relative; width: min(760px, 96%); margin: 16px auto 0; }
  .hero-art :global(img) { display: block; width: 100%; height: auto; }
  .how-it-works { padding-block: 38px 66px; }
  .section-heading { text-align: center; margin-bottom: 27px; }
  .section-heading .eyebrow { color: var(--orange); margin-bottom: 12px; }
  h2 { margin: 0; font-size: clamp(32px, 3.5vw, 43px); line-height: 1.15; letter-spacing: -.045em; }
  .section-heading > p:last-child { margin: 15px 0 0; font-size: 15px; line-height: 1.55; color: var(--muted); }
  .providers { display: flex; justify-content: center; align-items: center; flex-wrap: wrap; gap: 25px; margin-top: 30px; font-size: 13px; }
  .providers > span:first-child { color: var(--muted); }
  .provider { display: inline-flex; align-items: center; gap: 8px; }
  .provider strong { font-size: 14px; font-weight: 650; }
  .provider img { object-fit: contain; }
  .provider:nth-child(2) img { filter: brightness(0); }
  .installation { display: grid; grid-template-columns: 1fr 1fr; gap: 65px; padding-block: 46px 55px; border-top: 1px solid var(--line); align-items: center; }
  .install-copy { position: relative; padding-top: 12px; }
  .install-pet { display: block; height: 65px; margin-bottom: 10px; }
  .install-copy > p { margin: 15px 0 22px; font-size: 15px; line-height: 1.6; }
  .install-copy .install-hint { margin: 14px 0 0; font-size: 12px; color: var(--muted); }
  .install-options { min-width: 0; padding-top: 27px; }
  .terminal { overflow: hidden; border: 1px solid #d8dfd0; background: #edf0e7; border-radius: 12px; }
  .terminal-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 17px 5px; font-size: 12px; }
  .terminal-header > span { color: #5c6c59; }
  .terminal button { display: flex; align-items: center; gap: 5px; min-height: 30px; border: 0; border-radius: 5px; padding: 4px 7px; color: var(--ink); background: transparent; font: inherit; cursor: pointer; }
  .terminal button:hover { background: #dce4d6; }
  pre { margin: 0; padding: 14px 21px 22px; white-space: pre-wrap; overflow-wrap: anywhere; }
  code { font: 12px/1.9 'SFMono-Regular', Consolas, monospace; user-select: all; }
  .copy-status { margin: 5px 0 0; font-size: 12px; line-height: 1.5; }
  .copy-status:empty { display: none; }
  .release-note { color: var(--muted); margin: 16px 0 12px; font-size: 12px; line-height: 1.6; }
  .release-note strong { color: var(--ink); font-weight: 600; }
  details { font-size: 12px; line-height: 1.6; }
  summary { cursor: pointer; width: fit-content; text-underline-offset: 3px; }
  summary:hover { text-decoration: underline; }
  details p { margin: 9px 0 0; max-width: 420px; color: var(--muted); }
  footer { display: flex; justify-content: space-between; gap: 20px; align-items: center; min-height: 78px; border-top: 1px solid var(--line); font-size: 12px; color: var(--muted); }
  @media (max-width: 800px) {
    .page-width { width: calc(100% - 48px); }
    .site-header { min-height: 78px; }
    .hero { padding-top: 32px; }
    h1 { max-width: 660px; margin-inline: auto; }
    .hero-description { font-size: 16px; max-width: 520px; }
    .hero-art { margin-top: 32px; width: 100%; }
    .how-it-works { padding-block: 62px 44px; }
    .installation { gap: 32px; }
    .installation h2 { font-size: 33px; }
    .terminal-header { padding-inline: 12px; }
    code { font-size: 11px; }
    pre { padding-inline: 16px; }
  }
  @media (max-width: 580px) {
    .page-width { width: calc(100% - 36px); }
    .site-header { min-height: 74px; gap: 12px; }
    .brand { font-size: 17px; gap: 5px; }
    .brand-pet { width: 32px; }
    .github-link { display: none; }
    .nav-download { padding: 9px 12px; font-size: 12px; gap: 5px; }
    .hero { padding-top: 28px; }
    .eyebrow { font-size: 11px; margin-bottom: 18px; gap: 5px; }
    h1 { font-size: clamp(43px, 11.3vw, 63px); line-height: 1.07; letter-spacing: -.06em; }
    h1 em { display: block; }
    .hero-description { font-size: 15px; line-height: 1.6; max-width: 340px; margin-top: 20px; }
    .desktop-break { display: none; }
    .hero-actions { gap: 17px; margin-top: 23px; flex-wrap: wrap; }
    .button { min-height: 46px; padding: 12px 19px; font-size: 14px; }
    .homebrew-link { font-size: 12px; gap: 4px; }
    .compatibility { font-size: 10px; gap: 6px; margin-top: 17px; }
    .hero-art { margin-top: 26px; }
    .how-it-works { padding-block: 49px 39px; }
    h2 { font-size: 32px; }
    .section-heading { margin-bottom: 21px; }
    .section-heading > p:last-child { max-width: 300px; margin-inline: auto; font-size: 14px; }
    .providers { gap: 15px; margin-top: 24px; }
    .providers > span:first-child { width: 100%; text-align: center; font-size: 11px; }
    .provider { gap: 6px; }
    .provider strong { font-size: 12px; }
    .provider img { width: 20px; height: 20px; }
    .installation { grid-template-columns: 1fr; gap: 29px; padding-block: 28px 35px; text-align: center; }
    .install-pet { width: 65px; margin-inline: auto; }
    .install-copy > p { font-size: 14px; margin-bottom: 20px; }
    .install-copy .install-hint { font-size: 11px; }
    .install-options { padding-top: 0; text-align: left; }
    .terminal-header { font-size: 12px; }
    pre { padding: 12px 17px 20px; }
    code { font-size: 12px; }
    footer { min-height: 90px; flex-direction: column; justify-content: center; gap: 8px; font-size: 11px; padding-block: 21px; text-align: center; }
  }
  @media (prefers-reduced-motion: reduce) {
    :global(html) { scroll-behavior: auto; }
    .button { transition: none; }
    .button:hover { transform: none; }
  }
</style>

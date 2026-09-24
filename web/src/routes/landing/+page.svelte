<script lang="ts">
  import { base } from '$app/paths';
  import { ArrowUpRight, Check, Copy, Download } from '@lucide/svelte';
  import SpriteCell from '$lib/components/sprite-cell.svelte';
  import MenuBarDemo from './MenuBarDemo.svelte';

  const repository = 'https://github.com/andytyler/codex-pet-bar';
  const releases = `${repository}/releases/latest`;
  const installCommand = 'brew install --cask andytyler/tap/codex-pet-bar\ncodex-pet-bar';
  const providers = [
    { name: 'Codex', image: 'CodexThreadGlyph.png', href: 'https://openai.com/codex/' },
    { name: 'Claude Code', image: 'ClaudeCodeCrab.svg', href: 'https://www.anthropic.com/claude-code' },
    { name: 'Cursor', image: 'CursorProviderIconLight.svg', href: 'https://cursor.com/' }
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
  <title>Codex Pet Bar — Your pet, in your menu bar.</title>
  <meta name="description" content="Bring your existing Codex pet to your Mac’s menu bar. It follows your coding agents and tells you when they need you. For Codex, Claude Code and Cursor." />
  <meta property="og:title" content="Codex Pet Bar — Your pet, in your menu bar." />
  <meta property="og:description" content="Bring your existing Codex pet to your Mac’s menu bar. It follows your coding agents and tells you when they need you." />
  <meta property="og:image" content={`${base}/artwork/codex-pet-bar-icon.png`} />
  <meta name="theme-color" content="#ffffff" />
</svelte:head>

<div class="landing" id="top">
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header page-width">
    <a href="#top" class="brand" aria-label="Codex Pet Bar home">
      <span class="brand-mark" aria-hidden="true"><SpriteCell src={`${base}/pets/goblin.webp`} state="idle" size={46} /></span>
      <span>Codex Pet Bar</span>
    </a>
    <nav aria-label="Main navigation">
      <a class="secondary-nav" href="#how-it-works">How it works</a>
      <a class="secondary-nav" href={repository} target="_blank" rel="noreferrer">GitHub</a>
      <a class="button header-cta" href={releases} target="_blank" rel="noreferrer">Get the app</a>
    </nav>
  </header>

  <main id="main">
    <section class="hero page-width" aria-labelledby="hero-title">
      <h1 id="hero-title">Your pet,<br />in your menu bar.</h1>
      <div class="hero-intro">
        <p class="hero-description">Bring your existing Codex pet to your Mac’s menu bar. It follows your coding agents and tells you when they need you.</p>
        <a class="button primary" href={releases} target="_blank" rel="noreferrer"><Download size={27} strokeWidth={1.8} />Download for Mac</a>
        <a class="install-link" href="#install">Install with Homebrew</a>
        <p class="compatibility">macOS 14+ · Apple Silicon · Free &amp; open source</p>
        <p class="release-note">Previewing v0.2. Downloads and Homebrew currently install v0.1.2.</p>
      </div>
    </section>

    <div class="demo-shell page-width">
      <MenuBarDemo />
    </div>

    <section class="providers page-width" aria-label="Supported coding agents">
      <p>Works with your local agents</p>
      <div class="provider-links">
        {#each providers as provider (provider.name)}
          <a href={provider.href} target="_blank" rel="noreferrer">
            <img src={`${base}/landing-assets/${provider.image}`} alt="" width="42" height="42" />
            <span>{provider.name}</span>
          </a>
        {/each}
      </div>
    </section>

    <section class="features page-width" id="how-it-works" aria-labelledby="features-title">
      <h2 id="features-title">Small pet.<br />Useful signals.</h2>
      <ol class="feature-list">
        <li>
          <span class="feature-number" aria-hidden="true">01</span>
          <div>
            <h3>Know when you’re needed.</h3>
            <p>A provider flag tells you which task needs attention.</p>
          </div>
        </li>
        <li>
          <span class="feature-number" aria-hidden="true">02</span>
          <div>
            <h3>The context is one hover away.</h3>
            <p>See task summaries, grouped by project, without switching windows.</p>
          </div>
        </li>
        <li>
          <span class="feature-number" aria-hidden="true">03</span>
          <div>
            <h3>Your pet comes with you.</h3>
            <p>Automatically follows your selected Codex pet, including custom pets.</p>
          </div>
        </li>
      </ol>
    </section>

    <section class="installation" id="install" aria-labelledby="install-title">
      <div class="installation-inner page-width">
        <div class="install-intro">
          <h2 id="install-title">A new home<br />in your menu bar.</h2>
          <p>Install the app. Connect your agents. Get back to making things.</p>
        </div>
        <div class="install-steps">
          <div class="terminal" aria-label="Homebrew installation commands">
            <div class="terminal-header">
              <span class="window-controls" aria-hidden="true"><i></i><i></i><i></i></span>
              <span class="terminal-title">Terminal</span>
              <button class="copy-button" type="button" onclick={copyCommand} aria-label="Copy Homebrew install command">
                {#if copyState === 'copied'}<Check size={18} strokeWidth={1.7} />{:else}<Copy size={18} strokeWidth={1.7} />{/if}
                <span>{copyState === 'copied' ? 'Copied' : 'Copy'}</span>
              </button>
            </div>
            <pre><code><span class="command-line"><span class="prompt" aria-hidden="true">$</span>brew install --cask andytyler/tap/codex-pet-bar</span><span class="command-line"><span class="prompt" aria-hidden="true">$</span>codex-pet-bar</span></code></pre>
          </div>
          <div class={['copy-status', { visible: copyState === 'manual' }]} role="status" aria-live="polite">
            {#if copyState === 'copied'}Copied. Ready to paste into Terminal.{:else if copyState === 'manual'}Select and copy the command above; clipboard access is unavailable.{/if}
          </div>
          <div class="integration-instructions">
            <p><strong>In v0.2, choose Integrations → Install All in the pet menu.</strong></p>
            <p>Pet Bar will ask whether to open at login. Your choice, always.</p>
          </div>
          <div class="download-instructions">
            <a class="text-link" href={releases} target="_blank" rel="noreferrer">Prefer a download? Get the Mac app<ArrowUpRight size={19} strokeWidth={1.7} /></a>
            <p>Move CodexPetBar.app to Applications, then open it.</p>
          </div>
        </div>
      </div>
    </section>
  </main>

  <footer class="page-width">
    <a class="footer-brand" href="#top">Codex Pet Bar</a>
    <p>Runs locally on your Mac.</p>
    <a class="text-link" href={repository} target="_blank" rel="noreferrer">GitHub<ArrowUpRight size={18} strokeWidth={1.7} /></a>
  </footer>
</div>

<style>
  :global(html) { scroll-behavior: smooth; scroll-padding-top: 32px; }
  :global(body) { margin: 0; }
  .landing { --ink: #0c0c0e; --muted: #737780; --border: #dfe1e5; --orange: #ef542f; min-height: 100vh; background: #fff; color: var(--ink); font-family: 'Helvetica Neue', Helvetica, Arial, -apple-system, BlinkMacSystemFont, sans-serif; -webkit-font-smoothing: antialiased; }
  .landing :global(*) { box-sizing: border-box; }
  .landing :global(a) { color: inherit; }
  .landing :global(a), .landing :global(button) { -webkit-tap-highlight-color: transparent; }
  .landing :global(a:focus-visible), .landing :global(button:focus-visible) { outline: 3px solid var(--orange); outline-offset: 5px; }
  .landing :global(::selection) { background: #ffe0d7; color: var(--ink); }
  .page-width { width: min(1320px, calc(100% - 128px)); margin-inline: auto; }
  a { text-decoration: none; }
  .skip-link { position: fixed; z-index: 100; top: -80px; left: 24px; padding: 14px 20px; border-radius: 6px; background: var(--ink); }
  .landing .skip-link { color: #fff; }
  .skip-link:focus { top: 16px; }
  .site-header { height: 90px; display: flex; align-items: center; justify-content: space-between; gap: 24px; }
  .brand { display: inline-flex; align-items: center; gap: 13px; white-space: nowrap; font-size: 28px; line-height: 1.1; font-weight: 750; letter-spacing: -1.15px; }
  .brand-mark { display: flex; width: 46px; height: 50px; align-items: center; justify-content: center; }
  nav { display: flex; gap: 40px; align-items: center; font-size: 17px; line-height: 1.2; font-weight: 550; letter-spacing: -.3px; }
  nav a:not(.button):hover { text-decoration: underline; text-underline-offset: 5px; }
  .button { display: inline-flex; justify-content: center; align-items: center; gap: 19px; border: 1px solid transparent; border-radius: 10px; font-weight: 600; line-height: 1.2; letter-spacing: -.5px; transition: background 160ms ease, transform 160ms ease; }
  .button:hover { transform: translateY(-2px); }
  .landing .header-cta { min-height: 54px; padding: 14px 24px; color: #fff; background: var(--orange); font-size: 17px; }
  .header-cta:hover { background: #da4625; }
  .hero { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); align-items: start; gap: 52px; padding-block: 35px 28px; }
  h1 { margin: 0; font-size: clamp(55px, 6vw, 88px); font-weight: 750; line-height: 1.01; letter-spacing: -.066em; }
  .hero-intro { padding-top: 0; }
  .hero-description { margin: 0; font-size: 20px; line-height: 1.4; letter-spacing: -.4px; max-width: 600px; }
  .landing .primary { min-height: 60px; padding: 14px 26px; margin-top: 14px; background: var(--ink); color: #fff; font-size: 23px; }
  .primary:hover { background: #28292d; }
  .install-link { display: table; font-size: 20px; line-height: 1.3; letter-spacing: -.3px; margin-top: 12px; text-decoration: underline; text-underline-offset: 3px; }
  .install-link:hover, .text-link:hover { color: var(--orange); }
  .compatibility { margin: 18px 0 0; color: var(--muted); font-size: 15px; line-height: 1.5; letter-spacing: -.2px; }
  .release-note { margin: 9px 0 0; max-width: 380px; font-size: 12px; line-height: 1.5; color: #737780; }
  .providers { border-top: 1px solid var(--border); text-align: center; padding-block: 33px 43px; }
  .providers > p { margin: 0 0 20px; font-size: 16px; line-height: 1.4; color: var(--muted); letter-spacing: -.3px; }
  .provider-links { display: flex; align-items: center; justify-content: center; gap: 76px; }
  .provider-links a { display: inline-flex; align-items: center; gap: 15px; font-size: 24px; line-height: 1.2; font-weight: 550; letter-spacing: -.6px; }
  .provider-links a:hover span { text-decoration: underline; text-underline-offset: 5px; }
  .provider-links img { object-fit: contain; flex-shrink: 0; }
  .provider-links a:first-child img { filter: brightness(0); }
  .features { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 64px; padding-block: 63px 67px; }
  .features h2 { margin: 50px 0 0; font-size: clamp(48px, 4.7vw, 70px); line-height: 1.02; letter-spacing: -.058em; font-weight: 750; }
  .feature-list { list-style: none; margin: 0; padding: 0; }
  .feature-list li { display: grid; grid-template-columns: 39px minmax(0, 1fr); gap: 20px; border-top: 1px solid #cdd0d5; padding: 22px 0 30px; }
  .feature-list li:last-child { padding-bottom: 0; }
  .feature-number { color: var(--orange); font-size: 21px; line-height: 1.4; font-weight: 650; letter-spacing: -.6px; }
  .feature-list h3 { margin: 0 0 4px; font-size: 26px; line-height: 1.25; font-weight: 700; letter-spacing: -1px; }
  .feature-list p { margin: 0; color: var(--muted); font-size: 19px; line-height: 1.45; letter-spacing: -.3px; }
  .text-link { display: inline-flex; align-items: center; gap: 8px; text-decoration: underline; text-underline-offset: 4px; text-decoration-thickness: 1px; }
  .text-link :global(svg) { flex-shrink: 0; }
  .installation { background: #101112; color: #fff; }
  .installation-inner { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 64px; padding-block: 58px 50px; }
  .install-intro { padding-top: 41px; }
  .installation h2 { margin: 0; font-size: clamp(44px, 4.5vw, 67px); line-height: 1.04; font-weight: 750; letter-spacing: -.048em; }
  .install-intro > p { max-width: 630px; margin: 24px 0 0; font-size: 19px; line-height: 1.5; color: #b5b7be; letter-spacing: -.35px; }
  .install-steps { min-width: 0; }
  .terminal { border: 1px solid #37393b; border-radius: 9px; overflow: hidden; background: #1b1d1e; }
  .terminal-header { display: flex; align-items: center; gap: 24px; min-height: 47px; padding: 8px 17px; background: #242729; border-bottom: 1px solid #36383b; }
  .window-controls { display: flex; align-items: center; gap: 8px; }
  .window-controls i { display: block; width: 13px; height: 13px; background: #ff5d56; border-radius: 50%; }
  .window-controls i:nth-child(2) { background: #ffbe2f; }
  .window-controls i:nth-child(3) { background: #29c840; }
  .terminal-title { color: #b8bbc3; font-size: 15px; line-height: 1.4; }
  .copy-button { display: inline-flex; align-items: center; gap: 9px; padding: 5px 6px; margin-left: auto; border: 0; border-radius: 4px; background: transparent; color: #fff; font: inherit; font-size: 14px; line-height: 20px; cursor: pointer; }
  .copy-button:hover { background: #ffffff12; }
  pre { margin: 0; padding: 25px 21px 24px; overflow-x: auto; }
  code { display: block; font: 17px/1.8 'SFMono-Regular', Consolas, 'Liberation Mono', monospace; letter-spacing: -.25px; user-select: all; }
  .command-line { display: block; white-space: pre; }
  .prompt { display: inline-block; padding-right: 11px; color: var(--orange); user-select: none; }
  .copy-status { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  .copy-status.visible { position: static; width: auto; height: auto; clip-path: none; white-space: normal; padding-top: 8px; color: #d4d5d8; font-size: 13px; }
  .integration-instructions { margin-top: 23px; }
  .integration-instructions p { margin: 0; font-size: 18px; line-height: 1.55; color: #b5b7be; letter-spacing: -.3px; }
  .integration-instructions strong { color: #fff; font-weight: 650; }
  .download-instructions { margin-top: 34px; }
  .download-instructions a { font-size: 18px; line-height: 1.45; letter-spacing: -.3px; }
  .download-instructions p { margin: 6px 0 0; color: #b5b7be; font-size: 16px; line-height: 1.5; letter-spacing: -.25px; }
  footer { display: flex; align-items: center; justify-content: space-between; gap: 28px; min-height: 99px; padding-block: 26px; }
  .footer-brand { font-size: 22px; line-height: 1.2; font-weight: 700; letter-spacing: -.6px; }
  footer p { margin: 0; color: var(--muted); font-size: 16px; line-height: 1.5; letter-spacing: -.3px; }
  footer .text-link { font-size: 17px; line-height: 1.4; }
  @media (max-width: 1190px) {
    .page-width { width: calc(100% - 80px); }
    .hero { grid-template-columns: 1.25fr 1fr; gap: 36px; }
    h1 { font-size: clamp(50px, 5.7vw, 74px); }
    .hero-description { font-size: 20px; }
    .compatibility { font-size: 13px; }
    .features, .installation-inner { gap: 40px; }
    .feature-list h3 { font-size: 23px; }
    .feature-list p { font-size: 17px; }
    .feature-list li { grid-template-columns: 28px minmax(0, 1fr); gap: 16px; }
    .installation h2 { font-size: 52px; }
    code { font-size: 14px; }
    .integration-instructions p, .download-instructions a, .install-intro > p { font-size: 17px; }
    .download-instructions p { font-size: 14px; }
  }
  @media (max-width: 800px) {
    .page-width { width: calc(100% - 48px); }
    .site-header { height: 78px; gap: 14px; }
    .brand { font-size: 22px; gap: 8px; letter-spacing: -.8px; }
    .brand-mark { width: 35px; height: 40px; }
    .brand-mark :global(.cell) { transform: scale(.8); }
    nav { gap: 20px; }
    .secondary-nav { display: none; }
    .landing .header-cta { min-height: 43px; padding: 11px 15px; font-size: 14px; border-radius: 8px; }
    .hero { grid-template-columns: 1fr; gap: 27px; padding-block: 35px 36px; }
    h1 { font-size: clamp(48px, 8.6vw, 68px); line-height: 1.04; letter-spacing: -.064em; }
    .hero-intro { max-width: 550px; }
    .hero-description { font-size: 20px; line-height: 1.45; letter-spacing: -.3px; }
    .landing .primary { margin-top: 22px; min-height: 58px; padding: 15px 23px; font-size: 20px; gap: 13px; }
    .install-link { font-size: 17px; margin-top: 15px; }
    .compatibility { font-size: 12px; margin-top: 20px; line-height: 1.6; }
    .providers { padding-block: 25px 33px; }
    .providers > p { font-size: 14px; margin-bottom: 21px; }
    .provider-links { gap: 29px; }
    .provider-links a { gap: 10px; font-size: 18px; letter-spacing: -.3px; }
    .provider-links img { width: 31px; height: 31px; }
    .features { grid-template-columns: 1fr; gap: 33px; padding-block: 43px 48px; }
    .features h2 { margin: 0; font-size: 54px; letter-spacing: -.06em; }
    .feature-list li { padding-block: 23px 27px; grid-template-columns: 29px minmax(0, 1fr); gap: 17px; }
    .feature-list h3 { font-size: 24px; line-height: 1.2; letter-spacing: -.9px; }
    .feature-list p { font-size: 18px; line-height: 1.5; }
    .feature-number { font-size: 18px; }
    .installation-inner { grid-template-columns: 1fr; gap: 32px; padding-block: 45px 43px; }
    .install-intro { padding: 0; }
    .installation h2 { font-size: 50px; line-height: 1.05; letter-spacing: -.055em; }
    .install-intro > p { font-size: 18px; line-height: 1.55; margin-top: 19px; }
    .terminal-header { min-height: 44px; padding-inline: 13px; gap: 17px; }
    .terminal-title, .copy-button { font-size: 13px; }
    .window-controls { gap: 7px; }
    .window-controls i { width: 11px; height: 11px; }
    pre { padding: 21px 16px; }
    code { font-size: 13px; line-height: 1.85; }
    .command-line { white-space: pre-wrap; overflow-wrap: anywhere; padding-left: 17px; text-indent: -17px; }
    .prompt { padding-right: 8px; }
    .integration-instructions { margin-top: 22px; }
    .integration-instructions p { font-size: 17px; line-height: 1.55; }
    .integration-instructions p + p { margin-top: 6px; }
    .download-instructions { margin-top: 27px; }
    .download-instructions a { font-size: 17px; gap: 5px; }
    .download-instructions p { font-size: 15px; }
    footer { min-height: 110px; flex-wrap: wrap; gap: 18px; padding-block: 26px; }
    .footer-brand { font-size: 21px; }
    footer p { order: 3; width: 100%; font-size: 14px; }
    footer .text-link { font-size: 16px; }
  }
  @media (max-width: 480px) {
    h1 { font-size: clamp(32px, 10.4vw, 46px); }
    .brand { font-size: 20px; gap: 6px; }
    .brand-mark { width: 32px; }
    .landing .header-cta { font-size: 13px; padding-inline: 13px; }
    .hero-description { font-size: 18px; }
    .provider-links { justify-content: space-between; gap: 14px; }
    .provider-links a { flex-direction: column; gap: 10px; font-size: 16px; }
    .provider-links img { width: 34px; height: 34px; }
    .features h2 { font-size: 48px; }
    .installation h2 { font-size: 44px; }
  }
  @media (prefers-reduced-motion: reduce) {
    :global(html) { scroll-behavior: auto; }
    .button { transition: none; }
    .button:hover { transform: none; }
  }
</style>

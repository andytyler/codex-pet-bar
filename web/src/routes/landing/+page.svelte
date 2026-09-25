<script lang="ts">
  import '@fontsource-variable/dm-sans';
  import { base } from '$app/paths';
  import { ArrowUpRight, Check, Copy, Download } from '@lucide/svelte';
  import SpriteCell from '$lib/components/sprite-cell.svelte';
  import MenuBarDemo from './MenuBarDemo.svelte';
  const repository = 'https://github.com/andytyler/codex-pet-bar';
  const releases = `${repository}/releases/latest`;
  const installCommand = 'brew install --cask andytyler/tap/codex-pet-bar\ncodex-pet-bar';
  let copyState = $state<'idle' | 'copied' | 'manual'>('idle');
  async function copyCommand() {
    try { await navigator.clipboard.writeText(installCommand); copyState = 'copied'; }
    catch { copyState = 'manual'; }
  }
</script>

<svelte:head>
  <title>Codex Pet Bar — Your Codex pet, in your menu bar.</title>
  <meta name="description" content="Bring your existing Codex pet to your Mac’s menu bar. See when your coding agents are working or need your attention. Free and open source." />
  <link rel="canonical" href="https://pet.ajt.dev/" />
  <meta property="og:url" content="https://pet.ajt.dev/" />
  <meta property="og:title" content="Codex Pet Bar" />
  <meta property="og:description" content="Your Codex pet, in your menu bar. A free, open-source app for Mac." />
  <meta property="og:image" content="https://pet.ajt.dev/artwork/open-graph/codex-pet-bar-og-clean-hero.png" />
  <meta name="theme-color" content="#fafafa" />
</svelte:head>

<div class="landing" id="top">
  <a class="skip-link" href="#main">Skip to content</a>
  <div class="page-width">
    <header class="site-header">
      <a href="#top" class="brand" aria-label="Codex Pet Bar home"><span class="brand-pet" aria-hidden="true"><SpriteCell src={`${base}/pets/goblin.webp`} state="idle" size={32} /></span>Codex Pet Bar</a>
      <a class="source-link" href={repository} target="_blank" rel="noreferrer">Open source <ArrowUpRight size={15} /></a>
    </header>
    <main id="main">
      <section class="hero" aria-labelledby="hero-title">
        <div class="hero-copy">
          <h1 id="hero-title">Your Codex pet,<br />in your menu bar.</h1>
          <p>A little company while you code.<br />Bring the pet you already have and keep<br class="wide-break" /> an eye on what your agents are doing.</p>
          <div class="hero-actions">
            <a class="download" href={releases} target="_blank" rel="noreferrer"><Download size={17} />Download for Mac</a>
            <a class="brew-link" href="#install">Homebrew</a>
          </div>
          <p class="requirements">Free · macOS 14+ · Apple Silicon</p>
        </div>
        <figure class="hero-art">
          <enhanced:img src="$lib/assets/codex-pets.png" alt="The Codex pets gathered around a bar, with the green goblin in the middle." sizes="(min-width: 901px) 520px, (min-width: 601px) 65vw, 100vw" fetchpriority="high" />
          <figcaption>Your existing pet comes with you.</figcaption>
        </figure>
      </section>
      <section class="preview" aria-labelledby="preview-title">
        <div class="preview-heading"><div><h2 id="preview-title">Less checking. More coding.</h2><p>Your pet waves when a task needs you. Click it for the details.</p></div><span class="preview-label">Try it below ↓</span></div>
        <MenuBarDemo />
        <p class="agent-support">Works with <strong>Codex</strong>, <strong>Claude Code</strong> and <strong>Cursor</strong>.</p>
      </section>
      <section class="setup" id="install" aria-labelledby="install-title">
        <div class="setup-copy">
          <h2 id="install-title">Install. Open. There’s your pet.</h2>
          <p>Move CodexPetBar.app to Applications, then open it.<br />It picks up your existing Codex pet automatically.</p>
          <p class="release-note">Available now: <a href={releases} target="_blank" rel="noreferrer">v0.1.2 <ArrowUpRight size={12} /></a>. The demo previews v0.2.</p>
          <details><summary>What’s new in the v0.2 preview?</summary><p>Task summaries, agent connections and an option to open at login. You choose whether to enable it.</p></details>
        </div>
        <div class="terminal-wrap">
          <div class="terminal">
            <div class="terminal-header"><span>Install with Homebrew</span><button type="button" onclick={copyCommand} aria-label="Copy Homebrew install command">{#if copyState === 'copied'}<Check size={15} />{:else}<Copy size={15} />{/if}{copyState === 'copied' ? 'Copied' : 'Copy'}</button></div>
            <pre><code>{installCommand}</code></pre>
          </div>
          <p class="copy-status" role="status">{copyState === 'copied' ? 'Copied to clipboard.' : copyState === 'manual' ? 'Select and copy the command above; clipboard access is unavailable.' : ''}</p>
        </div>
      </section>
    </main>
    <footer><span>Made by <a href="https://ajt.dev" target="_blank" rel="noreferrer">Andy</a></span><a href={repository} target="_blank" rel="noreferrer">GitHub <ArrowUpRight size={13} /></a></footer>
  </div>
</div>

<style>
  :global(html) { scroll-behavior:smooth; scroll-padding-top:28px; }
  :global(body) { margin:0; }
  .landing { --ink:#202124; --muted:#707174; --line:#e1e2e4; background:#fafafa; color:var(--ink); min-height:100vh; font-family:'DM Sans Variable',sans-serif; -webkit-font-smoothing:antialiased; }
  .landing :global(*) { box-sizing:border-box; }
  .landing :global(a) { color:inherit; }
  .landing :global(a:focus-visible),.landing :global(button:focus-visible),summary:focus-visible { outline:2px solid #2768d8; outline-offset:5px; }
  a { text-decoration:none; }
  .page-width { width:min(1060px,calc(100% - 96px)); margin-inline:auto; }
  .skip-link { position:fixed; top:-80px; left:20px; z-index:20; padding:12px 18px; background:white; border:1px solid var(--line); border-radius:5px; }
  .skip-link:focus { top:16px; }
  .site-header { min-height:92px; display:flex; justify-content:space-between; align-items:center; gap:20px; }
  .brand { display:flex; align-items:center; gap:9px; font-size:15px; font-weight:700; letter-spacing:-.3px; }
  .brand-pet { width:32px; height:35px; }
  .source-link { display:inline-flex; align-items:center; gap:6px; color:var(--muted); font-size:13px; }
  .source-link:hover,.brew-link:hover,footer a:hover { text-decoration:underline; text-underline-offset:4px; }
  .hero { display:grid; grid-template-columns:1fr 1fr; align-items:center; gap:6px; padding:65px 0 78px; }
  h1 { margin:0; font-size:clamp(36px,4.3vw,52px); font-weight:650; line-height:1.08; letter-spacing:-.055em; }
  .hero-copy > p { margin:22px 0 0; font-size:16px; line-height:1.65; color:#64666b; letter-spacing:-.15px; }
  .hero-actions { display:flex; align-items:center; gap:24px; margin-top:26px; }
  .download { display:inline-flex; justify-content:center; align-items:center; gap:9px; min-height:44px; padding:11px 17px; background:#242528; border:1px solid #242528; border-radius:7px; font-size:14px; font-weight:550; }
  .landing .download { color:white; }
  .download:hover { background:#404145; }
  .brew-link { font-size:13px; }
  .hero-copy > .requirements { margin-top:13px; font-size:11px; letter-spacing:.1px; color:var(--muted); }
  .hero-art { margin:0 -20px 0 0; }
  .hero-art :global(img) { display:block; width:100%; height:auto; }
  figcaption { margin:-3px 0 0; text-align:center; font-size:11px; color:#797a7e; }
  .preview { border-top:1px solid var(--line); padding-top:32px; }
  .preview-heading { display:flex; align-items:center; justify-content:space-between; gap:24px; margin-bottom:25px; }
  h2 { margin:0; font-size:20px; line-height:1.3; font-weight:600; letter-spacing:-.55px; }
  .preview-heading p { margin:7px 0 0; color:var(--muted); font-size:13px; line-height:1.6; }
  .preview-label { flex-shrink:0; font-size:12px; color:var(--muted); }
  .agent-support { margin:20px 0 0; font-size:12px; text-align:center; color:var(--muted); }
  .agent-support strong { font-weight:500; color:#3d3e41; }
  .setup { display:grid; grid-template-columns:1fr 1fr; gap:48px; padding-block:50px; margin-top:40px; border-top:1px solid var(--line); align-items:start; }
  .setup-copy > p { font-size:13px; line-height:1.75; color:var(--muted); margin:12px 0 0; }
  .setup-copy .release-note { font-size:11px; margin-top:16px; }
  .release-note a { display:inline-flex; align-items:center; gap:2px; text-decoration:underline; text-underline-offset:2px; }
  details { margin-top:9px; font-size:11px; line-height:1.7; }
  summary { cursor:pointer; color:var(--muted); width:fit-content; }
  details p { margin:7px 0 0; max-width:365px; color:var(--muted); }
  .terminal-wrap { min-width:0; }
  .terminal { background:#f1f1f2; border:1px solid var(--line); border-radius:8px; overflow:hidden; }
  .terminal-header { display:flex; justify-content:space-between; align-items:center; gap:10px; padding:12px 16px 0; font-size:11px; color:var(--muted); }
  .terminal button { display:flex; align-items:center; gap:5px; min-height:30px; border:0; padding:5px; background:transparent; color:inherit; font:inherit; cursor:pointer; }
  .terminal button:hover { color:var(--ink); }
  pre { margin:0; padding:12px 18px 20px; white-space:pre-wrap; overflow-wrap:anywhere; }
  code { font:11px/1.9 'SFMono-Regular',Consolas,monospace; user-select:all; }
  .copy-status { margin:6px 0 0; color:var(--muted); font-size:11px; }
  .copy-status:empty { display:none; }
  footer { display:flex; justify-content:space-between; align-items:center; gap:20px; min-height:78px; border-top:1px solid var(--line); color:var(--muted); font-size:12px; }
  footer > a { display:inline-flex; gap:5px; align-items:center; }
  footer span a { text-decoration:underline; text-underline-offset:3px; }
  @media (max-width:900px) {
    .page-width { width:calc(100% - 64px); } .hero { padding-block:48px 60px; } h1 { font-size:40px; } .hero-copy > p { font-size:14px; } .wide-break { display:none; } .hero-art { margin-right:-16px; } .hero-actions { gap:18px; } .setup { gap:28px; }
  }
  @media (max-width:650px) {
    .page-width { width:calc(100% - 40px); } .site-header { min-height:76px; } .brand { font-size:14px; } .source-link { font-size:12px; } .hero { grid-template-columns:1fr; gap:26px; padding:36px 0 38px; } h1 { font-size:clamp(37px,9.5vw,52px); line-height:1.1; } .hero-copy > p { margin-top:17px; font-size:15px; } .hero-actions { margin-top:23px; } .hero-art { margin:0 auto; width:min(450px,100%); } figcaption { margin-top:0; } .preview { padding-top:25px; } .preview-heading { align-items:start; margin-bottom:21px; } .preview-label { display:none; } h2 { font-size:20px; } .preview-heading p { max-width:295px; font-size:13px; } .agent-support { font-size:11px; } .setup { grid-template-columns:1fr; gap:24px; margin-top:28px; padding-block:30px; } code { font-size:11px; } footer { min-height:72px; }
  }
  @media (prefers-reduced-motion:reduce) { :global(html) { scroll-behavior:auto; } }
</style>

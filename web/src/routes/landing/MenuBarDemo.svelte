<script lang="ts">
  import { base } from '$app/paths';
  import { onDestroy } from 'svelte';
  import { ChevronRight } from '@lucide/svelte';
  import SpriteCell, { type SpriteState } from '$lib/components/sprite-cell.svelte';

  type DemoState = 'working' | 'attention' | 'idle';
  const providers = [
    { id: 'codex', name: 'Codex', mark: `${base}/landing-assets/CodexThreadGlyph.png`, app: `${base}/landing-assets/CodexProviderAppIcon.png` },
    { id: 'claude', name: 'Claude Code', mark: `${base}/landing-assets/ClaudeCodeCrab.svg`, app: `${base}/landing-assets/ClaudeCodeCrab.svg` },
    { id: 'cursor', name: 'Cursor', mark: `${base}/landing-assets/CursorProviderIconLight.svg`, app: `${base}/landing-assets/CursorProviderIconLight.svg` }
  ];
  const controls: { id: DemoState; label: string; description: string }[] = [
    { id: 'working', label: 'Working', description: 'Your agents are moving things along.' },
    { id: 'attention', label: 'Needs attention', description: 'A task is waiting for your input.' },
    { id: 'idle', label: 'Idle', description: 'All quiet. Your pet takes a breather.' }
  ];

  const petSource = `${base}/pets/goblin.webp`;
  let selectedState = $state<DemoState>('attention');
  let panelOpen = $state(true);
  let panelPinned = $state(false);
  let closeTimer: ReturnType<typeof setTimeout> | undefined;
  const animation = $derived<SpriteState>(selectedState === 'attention' ? 'waving' : selectedState === 'working' ? 'running' : 'idle');
  const status = $derived(selectedState === 'idle' ? '0 active tasks' : '3 active tasks');
  const summary = $derived(selectedState === 'attention'
    ? 'Claude Code is waiting for permission. Your other two tasks are still running.'
    : selectedState === 'working'
      ? 'Three local tasks are running across Codex, Claude Code, and Cursor.'
      : 'All quiet. Your pet sleeps until the next task comes along.');
  const tasks = $derived([
    { provider: providers[0], title: 'Build the settings page', summary: 'Building the form fields.', waiting: false },
    { provider: providers[1], title: 'Run the tests', summary: selectedState === 'attention' ? 'Waiting for permission to run the tests.' : 'Running the test suite.', waiting: selectedState === 'attention' },
    { provider: providers[2], title: 'Update the docs', summary: 'Updating the setup instructions.', waiting: false }
  ]);

  function cancelClose() {
    if (closeTimer) clearTimeout(closeTimer);
  }
  function showPanel() {
    cancelClose();
    panelOpen = true;
  }
  function leavePanel(event: PointerEvent) {
    cancelClose();
    const anchor = event.currentTarget as HTMLElement;
    if (panelPinned || anchor.contains(document.activeElement)) return;
    closeTimer = setTimeout(() => (panelOpen = false), 180);
  }
  function focusPanel(event: FocusEvent) {
    const element = event.target as HTMLElement;
    if (element.matches(':focus-visible')) showPanel();
  }
  function blurPanel(event: FocusEvent) {
    const anchor = event.currentTarget as HTMLElement;
    if (!panelPinned && !anchor.contains(event.relatedTarget as Node | null)) panelOpen = false;
  }
  function togglePanel() {
    cancelClose();
    // Pointer entry may already have revealed the hover panel. The first tap or
    // click pins it, rather than immediately hiding what pointer entry opened.
    panelOpen = !panelPinned;
    panelPinned = panelOpen;
  }
  function closeOnEscape(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    cancelClose();
    panelOpen = false;
    panelPinned = false;
  }
  function chooseState(next: DemoState) {
    cancelClose();
    selectedState = next;
    panelPinned = false;
    panelOpen = next !== 'idle';
  }
  onDestroy(cancelClose);
</script>

<svelte:window onkeydown={closeOnEscape} />

<div class="menu-bar-demo">
  <div class="playground-controls">
    <h2>Your pet, on duty.</h2>
    <p class="playground-description">Open Pet Bar. Your selected Codex pet comes with you.</p>
    <fieldset class="state-controls">
      <legend class="sr-only">Preview a task state</legend>
      {#each controls as control (control.id)}
        <button type="button" class="state-choice" aria-label={control.label} aria-pressed={selectedState === control.id} onclick={() => chooseState(control.id)}>
          <span class={['control-dot', control.id]} aria-hidden="true"></span>
          <span class="state-label"><strong>{control.label}</strong><span>{control.description}</span></span>
          <ChevronRight size={19} strokeWidth={1.5} />
        </button>
      {/each}
    </fieldset>
  </div>
  <div class="desktop-stage" style:background-image={`url(${base}/landing-assets/desktop-wallpaper.jpg)`}>
    <div class="mac-menu" aria-hidden="true">
      <div class="mac-menu-left">
        <svg class="apple-symbol" viewBox="0 0 20 22" fill="currentColor"><path d="M13.9 3.5c.8-.9 1.2-2 1.1-3.1-1.1.1-2.3.8-3 1.6-.7.8-1.3 2-1.1 3 1.2.1 2.3-.5 3-1.5Zm3.8 8.1c0-2.5 2-3.7 2.1-3.8-1.2-1.7-3-1.9-3.7-2-1.6-.1-3 1-3.8 1-.9 0-2.1-1-3.5-.9C7 6 5.3 7 4.4 8.6c-1.8 3.2-.5 7.9 1.2 10.4.8 1.2 1.8 2.6 3.1 2.5 1.3 0 1.7-.8 3.3-.8s2 .8 3.5.8c1.4 0 2.2-1.3 3-2.5.9-1.4 1.3-2.7 1.4-2.8-.1 0-2.2-.9-2.2-4.6Z" transform="translate(-2 0)" /></svg>
        <strong>Finder</strong><span>File</span><span>Edit</span><span class="extra-menu">View</span><span class="extra-menu">Go</span>
      </div>
      <div class="mac-menu-right">
        <svg class="wifi" viewBox="0 0 20 16" fill="none"><path d="M1 4.5a14 14 0 0 1 18 0M4 7.5a9 9 0 0 1 12 0M7 10.5a4.7 4.7 0 0 1 6 0" /><circle cx="10" cy="13.5" r="1" fill="currentColor" stroke="none" /></svg>
        <span class="battery"><i></i></span>
        <span class="clock">9:41</span>
      </div>
    </div>

    <div
      class={['task-anchor', { idle: selectedState === 'idle' }]}
      role="group"
      aria-label="Menu bar pet and example tasks"
      onpointerenter={showPanel}
      onpointerleave={leavePanel}
      onfocusin={focusPanel}
      onfocusout={blurPanel}
    >
      <button
        type="button"
        class={['pet-button', { attention: selectedState === 'attention', idle: selectedState === 'idle' }]}
        aria-label={`Example pet: ${status}. ${panelPinned ? 'Hide' : 'Pin'} task summaries.`}
        aria-expanded={panelOpen}
        aria-controls="example-task-panel"
        onclick={togglePanel}
      >
        <span class="pet-and-flag" aria-hidden="true">
          <span class="menubar-pet">
            {#if selectedState === 'idle'}
              <span class="sleeping-pet"><span class="sleep-sprite" style:background-image={`url(${petSource})`}></span><span class="sleep-z first">z</span><span class="sleep-z second">z</span></span>
            {:else}
              <SpriteCell src={petSource} state={animation} size={43} />
            {/if}
          </span>
          {#if selectedState === 'attention'}
            <svg class="held-flag" viewBox="0 0 43 39" fill="none">
              <path d="M3 4v31" stroke="#52574d" stroke-width="1.8" stroke-linecap="round" />
              <path d="M4 5C15 7 25 3 35 5l-3.5 9 3.5 8c-11 3-21-1-31 1V5Z" fill="#ffe1cc" stroke="#cb7856" stroke-width="1.2" />
              <path d="M5 6c10 2 20-1 28 0" stroke="#fff5ec" stroke-width="2" />
              <image href={`${base}/landing-assets/ClaudeCodeCrab.svg`} x="10" y="8" width="18" height="15" />
            </svg>
          {/if}
        </span>
        {#if selectedState !== 'idle'}
          <span class="provider-flags" aria-hidden="true">
            {#each providers as provider (provider.id)}
              <span class={['provider-flag', { waiting: provider.id === 'claude' && selectedState === 'attention' }]}>
                <img src={provider.mark} alt="" class={{ 'codex-mark': provider.id === 'codex' }} />
              </span>
            {/each}
          </span>
        {/if}
      </button>

      {#if panelOpen}
        <section id="example-task-panel" class="task-panel" aria-label="Example local task summaries">
          <header class="panel-header">
            <strong>Goblin</strong><span>· {status}</span>
            {#if selectedState !== 'idle'}
              <span class="header-providers" aria-hidden="true">{#each providers as provider (provider.id)}<img src={provider.app} alt="" />{/each}</span>
            {/if}
          </header>
          {#if selectedState === 'idle'}
            <div class="idle-summary"><strong>Nothing needs you right now.</strong><p>Your pet will wake up when a task starts.</p></div>
          {:else}
          <p class="project-label"><svg viewBox="0 0 18 16" fill="none" aria-hidden="true"><path d="M2 3a1 1 0 0 1 1-1h4l2 2h6a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3Z" /><path d="M2 6h14" /></svg> website</p>
          <ul class="task-list">
            {#each tasks as task (task.provider.id)}
              <li class="task-row">
                <img src={task.provider.app} alt={task.provider.name} class="task-provider" />
                <div class="task-copy"><strong>{task.title}</strong><p>{task.summary}</p></div>
                <span class={['task-state', { waiting: task.waiting }]}>
                  {#if task.waiting}
                    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M7 10V5a1.2 1.2 0 0 1 2.4 0v4-6a1.2 1.2 0 0 1 2.4 0v6-5a1.2 1.2 0 0 1 2.4 0v6-3a1.2 1.2 0 0 1 2.4 0v5c0 4-2 6-5 6-2 0-3-.8-4.2-2.3L4.6 12a1.3 1.3 0 0 1 2-1.7L8 12" /></svg><span class="sr-only">Waiting for permission</span>
                  {:else}
                    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M16 7a6.5 6.5 0 0 0-11-2L3 7m0-4v4h4M4 13a6.5 6.5 0 0 0 11 2l2-2m0 4v-4h-4" /></svg><span class="sr-only">Running</span>
                  {/if}
                </span>
              </li>
            {/each}
          </ul>
          {/if}
        </section>
      {/if}
    </div>

    <div class={['state-caption', selectedState]} aria-live="polite" aria-atomic="true">
      <span class="caption-indicator" aria-hidden="true">{selectedState === 'attention' ? '!' : selectedState === 'working' ? '↻' : 'z'}</span>
      <div><strong>{selectedState === 'attention' ? 'Claude needs your permission.' : selectedState === 'working' ? 'Your agents are on it.' : 'All quiet. Take a breather.'}</strong>
      <p>{selectedState === 'attention' ? 'Your other agents are still working.' : selectedState === 'working' ? 'Three tasks, quietly moving along.' : 'Your pet will wake up with your next task.'}</p></div>
    </div>
    <p class="sr-only">Interactive example: {summary}</p>
  </div>


</div>

<style>
  .menu-bar-demo { display:grid; grid-template-columns:440px minmax(0,1fr); gap:48px; padding-block:4px 36px; align-items:start; width:100%; margin:0; color:#141518; font-family:'Helvetica Neue',Helvetica,Arial,sans-serif; }
  .desktop-stage { position:relative; height:360px; background-color:#d8daf7; background-size:cover; background-position:center; border-radius:8px; box-shadow:0 4px 15px #3838540c; }
  .mac-menu { display:flex; justify-content:space-between; align-items:center; height:44px; padding-inline:26px; background:#f8f8ffb8; border-radius:8px 8px 0 0; color:#17171c; }
  .mac-menu-left,.mac-menu-right { display:flex; align-items:center; gap:24px; font-size:14px; line-height:1; }
  .mac-menu-left strong { font-weight:650; }
  .apple-symbol { height:18px; width:18px; margin-right:3px; }
  .mac-menu-right { gap:19px; }
  .wifi { width:18px; height:16px; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; }
  .battery { position:relative; width:23px; height:11px; border:1px solid #555560; border-radius:3px; padding:1px; }
  .battery::after { content:''; position:absolute; width:2px; height:4px; right:-4px; top:2.5px; background:#555560; border-radius:0 1px 1px 0; }
  .battery i { display:block; width:15px; height:7px; background:#444450; border-radius:1px; }
  .clock { font-variant-numeric:tabular-nums; margin-left:3px; }
  .task-anchor { position:absolute; z-index:2; right:157px; top:0; width:206px; height:44px; transition:width 320ms cubic-bezier(.2,.8,.2,1); }
  .task-anchor.idle { width:51px; }
  button { font:inherit; color:inherit; cursor:pointer; }
  .pet-button { display:flex; align-items:center; justify-content:flex-end; gap:12px; width:100%; height:44px; padding:0 6px; background:transparent; border:0; border-radius:5px; }
  .pet-button:hover { background:#ffffff50; }
  .pet-button:focus-visible,.state-choice:focus-visible { outline:2px solid #ef542f; outline-offset:3px; }
  .pet-and-flag { position:relative; display:flex; align-items:center; width:69px; height:44px; flex:0 0 69px; }
  .menubar-pet { display:block; width:43px; height:47px; margin-left:4px; }
  .sleeping-pet { position:relative; display:block; width:43px; height:47px; }
  .sleep-sprite { display:block; width:43px; height:47px; background-position:-86px 0; background-size:344px 423px; background-repeat:no-repeat; image-rendering:pixelated; animation:sleep-breathe 3.6s ease-in-out infinite; }
  .sleep-z { position:absolute; color:#686879; font-family:Georgia,serif; font-style:italic; font-weight:600; line-height:1; animation:sleep-drift 3.6s ease-in-out infinite; }
  .sleep-z.first { top:13px; right:7px; font-size:7px; }
  .sleep-z.second { top:6px; right:2px; font-size:9px; animation-delay:700ms; }
  .held-flag { position:absolute; top:4px; left:37px; height:34px; width:38px; transform-origin:4px 34px; animation:flag-wave 2.5s ease-in-out infinite; }
  .provider-flags { display:flex; align-items:center; gap:10px; padding-top:3px; }
  .provider-flag { position:relative; display:grid; place-items:center; width:21px; height:21px; flex:0 0 21px; }
  .provider-flag > img { display:block; width:19px; height:19px; object-fit:contain; }
  .provider-flag > img.codex-mark { filter:brightness(0); opacity:.85; }
  .provider-flag.waiting { border:1.4px solid #ef8a2f; border-radius:50%; padding:2px; animation:attention-pulse 2.5s ease-in-out infinite; }
  .provider-flag.waiting > img { width:15px; height:15px; }
  .pet-button.idle { gap:0; padding-inline:4px; }
  .pet-button.idle .pet-and-flag { width:43px; flex-basis:43px; }
  .pet-button.idle .menubar-pet { margin-left:0; }
  .idle-summary { padding:25px 2px 16px; }
  .idle-summary strong { display:block; font-size:16px; font-weight:550; }
  .idle-summary p { margin:8px 0 0; font-size:14px; line-height:1.5; color:#737780; }
  .task-panel { position:absolute; top:57px; right:-133px; width:360px; padding:14px 16px 10px; background:#fafafff5; color:#17181b; border:1px solid #ffffffd9; border-radius:14px; box-shadow:0 14px 30px #35365327,0 2px 6px #24243312; backdrop-filter:blur(20px); }
  .task-panel::before { content:''; position:absolute; top:-7px; right:259px; width:14px; height:14px; background:#fafaff; transform:rotate(45deg); border-radius:2px; }
  .panel-header { position:relative; display:flex; align-items:center; gap:6px; min-height:43px; font-size:15px; white-space:nowrap; border-bottom:1px solid #e3e3eb; padding-bottom:11px; }
  .panel-header > strong { font-size:17px; font-weight:650; }
  .panel-header > span { color:#737780; font-size:14px; }
  .header-providers { display:flex; align-items:center; gap:5px; margin-left:auto; }
  .header-providers img { width:17px; height:17px; object-fit:contain; }
  .project-label { display:flex; align-items:center; gap:7px; margin:13px 1px 4px; color:#737780; font-size:13px; font-weight:500; }
  .project-label svg { width:14px; height:13px; stroke:currentColor; stroke-width:1.2; stroke-linecap:round; stroke-linejoin:round; }
  .task-list { list-style:none; padding:0; margin:0; }
  .task-row { position:relative; display:flex; align-items:center; gap:11px; min-height:59px; padding:9px 0; }
  .task-row + .task-row::before { position:absolute; content:''; left:0; right:0; top:0; height:1px; background:#e1e2e8; }
  .task-provider { flex:0 0 29px; width:29px; height:29px; object-fit:contain; }
  .task-copy { min-width:0; flex:1; }
  .task-copy strong { display:block; font-size:14px; line-height:1.4; font-weight:550; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .task-copy p { margin:3px 0 0; font-size:12px; line-height:1.5; color:#737780; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .task-state { flex:0 0 18px; width:18px; height:18px; color:#28a963; }
  .task-state.waiting { color:#ef782f; }
  .task-state svg { width:18px; height:18px; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .playground-controls { padding-top:7px; }
  .playground-controls h2 { margin:0; font-size:27px; line-height:1.2; font-weight:700; letter-spacing:-1px; }
  .playground-description { margin:10px 0 0; font-size:19px; line-height:1.45; letter-spacing:-.4px; }
  .state-caption { position:absolute; left:22px; bottom:22px; display:flex; align-items:center; gap:11px; max-width:310px; border-left:3px solid #ef542f; padding:10px 13px; background:#ffffffd9; border-radius:3px 9px 9px 3px; color:#252531; }
  .caption-indicator { display:grid; place-items:center; flex:0 0 25px; width:25px; height:25px; border-radius:50%; background:#ef542f; color:white; font-size:16px; font-weight:600; }
  .state-caption strong { display:block; font-size:13px; font-weight:550; line-height:1.4; }
  .state-caption p { margin:2px 0 0; font-size:12px; color:#656579; line-height:1.4; }
  .state-caption.working { border-color:#3a926a; }
  .state-caption.working .caption-indicator { background:#3a926a; }
  .state-caption.idle { border-color:#8a80a6; }
  .state-caption.idle .caption-indicator { background:#8a80a6; }
  .state-controls { display:flex; flex-direction:column; border:0; padding:0; margin:27px 0 0; background:transparent; }
  .state-choice { display:flex; align-items:center; gap:16px; width:100%; min-height:78px; padding:13px 0; border:0; border-top:1px solid #dfe1e8; background:transparent; text-align:left; color:#15151b; cursor:pointer; }
  .state-choice:last-child { border-bottom:1px solid #dfe1e8; }
  .state-choice > :global(svg) { flex-shrink:0; color:#7d8495; margin-left:auto; transition:transform 160ms; }
  .state-choice:hover > :global(svg),.state-choice[aria-pressed='true'] > :global(svg) { transform:translateX(3px); color:#16161a; }
  .state-label { display:flex; flex-direction:column; gap:3px; }
  .state-label strong { font-size:16px; line-height:1.3; font-weight:650; letter-spacing:-.25px; }
  .state-label > span { font-size:13px; line-height:1.45; color:#737b8d; }
  .state-choice[aria-pressed='true'] strong { color:#d94220; }
  .control-dot { width:13px; height:13px; flex:0 0 13px; border-radius:50%; background:#bec3d1; }
  .control-dot.working { background:#29b861; }
  .control-dot.attention { background:#ef542f; }
  .sr-only { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip-path:inset(50%); white-space:nowrap; border:0; }
  @keyframes sleep-breathe { 0%,100% { transform:translateY(0); } 50% { transform:translateY(1px); } }
  @keyframes sleep-drift { 0%,100% { opacity:.35; transform:translateY(1px); } 50% { opacity:.85; transform:translateY(-1px); } }
  @keyframes attention-pulse { 0%,100% { transform:scale(1); } 50% { transform:scale(1.08); } }
  @keyframes flag-wave { 0%,100% { transform:rotate(-2deg); } 50% { transform:rotate(2deg); } }
  @media (max-width:1200px) {
    .menu-bar-demo { grid-template-columns:290px minmax(0,1fr); gap:30px; }
    .playground-controls h2 { font-size:24px; }
    .playground-description { font-size:17px; }
    .state-choice { gap:12px; }
    .state-label > span { font-size:12px; }
    .mac-menu-left > span { display:none; }
    .mac-menu-left { gap:12px; }
    .state-caption { left:16px; bottom:15px; padding:8px 10px; max-width:calc(100% - 408px); }
    .caption-indicator { display:none; }
  }
  @media (max-width:950px) {
    .menu-bar-demo { grid-template-columns:1fr; gap:25px; }
    .playground-controls { display:grid; grid-template-columns:1fr 1.3fr; align-items:start; column-gap:32px; }
    .playground-controls h2,.playground-description { grid-column:1; }
    .playground-description { margin-top:10px; }
    .state-controls { grid-column:2; grid-row:1 / 4; margin:0; }
    .desktop-stage { height:360px; }
    .state-caption { max-width:310px; }
    .caption-indicator { display:grid; }
  }
  @media (max-width:700px) {
    .playground-controls { display:block; }
    .playground-controls h2 { font-size:25px; }
    .playground-description { margin-top:8px; font-size:17px; max-width:360px; }
    .state-controls { margin:24px 0 0; }
    .state-choice { min-height:74px; }
    .state-label > span { font-size:13px; }
    .desktop-stage { height:440px; }
    .state-caption { left:15px; right:15px; bottom:16px; max-width:none; }
    .mac-menu { padding-inline:15px; height:47px; }
    .mac-menu-left { gap:11px; font-size:12px; }
    .mac-menu-right { display:none; }
    .task-anchor { right:14px; height:47px; width:194px; }
    .pet-button { height:47px; gap:8px; }
    .task-panel { top:62px; right:0; width:min(360px,calc(100vw - 78px)); padding:13px; }
    .task-panel::before { right:134px; }
    .panel-header { min-height:37px; gap:5px; }
    .panel-header > strong { font-size:15px; }
    .panel-header > span { font-size:12px; }
    .header-providers { gap:4px; }
    .header-providers img { width:14px; height:14px; }
    .task-row { min-height:59px; gap:8px; }
    .task-provider { width:25px; height:25px; flex-basis:25px; }
    .task-copy strong { font-size:13px; }
    .task-copy p { font-size:11px; }
  }
  @media (max-width:370px) {
    .mac-menu-left strong { display:none; }
    .task-anchor { right:10px; }
    .task-panel { width:calc(100vw - 68px); padding-inline:10px; right:-1px; }
    .header-providers { display:none; }
    .state-choice { gap:10px; }
    .state-label > span { font-size:12px; }
  }
  @media (prefers-reduced-motion:reduce) { .held-flag,.provider-flag.waiting,.sleep-sprite,.sleep-z { animation:none; } .state-choice,.task-anchor { transition:none; } }
</style>

<script lang="ts">
  import { ArrowUpRight, ChevronRight } from '@lucide/svelte';
  import SpriteCell, { type SpriteState } from '$lib/components/sprite-cell.svelte';

  const pets = [
    { id: 'goblin', name: 'Goblin' },
    { id: 'tock', name: 'Tock' },
    { id: 'boo', name: 'Boo' },
    { id: 'ajt', name: 'AJT' },
    { id: 'clippy', name: 'Clippy' },
    { id: 'grumble', name: 'Grumble' }
  ];

  const activities: { id: string; label: string; animation: SpriteState; message: string; caption: string }[] = [
    { id: 'idle', label: 'Idle', animation: 'idle', message: 'Enjoying a quiet moment.', caption: 'Ready when you are' },
    { id: 'working', label: 'Working', animation: 'running', message: 'Working on it…', caption: 'A little company while you build' },
    { id: 'waiting', label: 'Needs you', animation: 'waiting', message: 'A little help, please.', caption: 'Waiting for your attention' },
    { id: 'done', label: 'Done', animation: 'review', message: 'Ready for a look.', caption: 'Your work is ready to review' }
  ];

  let selectedPet = $state('goblin');
  let selectedActivity = $state('working');
  const pet = $derived(pets.find((item) => item.id === selectedPet) ?? pets[0]);
  const activity = $derived(activities.find((item) => item.id === selectedActivity) ?? activities[1]);
  const petSource = $derived(`/pets/${pet.id}.webp`);
</script>

<section id="companions" class="companions" aria-labelledby="companions-heading">
  <div class="section-inner">
    <div class="picker-heading">
      <h2 id="companions-heading">Pick your little plus-one.</h2>
      <p>Different personalities. Same good company.</p>
    </div>
    <fieldset class="pet-picker">
      <legend class="sr-only">Choose a pet for the interactive preview</legend>
      {#each pets as companion (companion.id)}
        <button
          type="button"
          class="pet-choice"
          aria-pressed={selectedPet === companion.id}
          onclick={() => (selectedPet = companion.id)}
        >
          <span class="picker-sprite"><SpriteCell src={`/pets/${companion.id}.webp`} state="idle" size={100} /></span>
          <span class="pet-name">{companion.name}</span>
        </button>
      {/each}
    </fieldset>
  </div>
</section>

<section id="how-it-works" class="activity-section" aria-labelledby="activity-heading">
  <div class="section-inner activity-layout">
    <div class="interactive-demo">
      <p class="preview-label">Interactive preview <ArrowUpRight size={16} aria-hidden="true" /></p>
      <div class="sample-window">
        <div class="sample-menubar" aria-hidden="true">
          <span class="window-controls"><i></i><i></i><i></i></span>
          <strong>Codex</strong>
          <span class="menu-item">File</span>
          <span class="menu-item">Edit</span>
          <span class="menubar-pet"><SpriteCell src={petSource} state={activity.animation} size={38} /></span>
        </div>
        <div class="sample-content" aria-live="polite" aria-atomic="true">
          <SpriteCell src={petSource} state={activity.animation} size={76} />
          <div class="sample-copy">
            <span class="sr-only">{pet.name}: </span>
            <p>{activity.message}</p>
            <span>{activity.caption}</span>
          </div>
        </div>
      </div>
      <fieldset class="activity-controls">
        <legend class="sr-only">Choose an activity for the interactive preview</legend>
        {#each activities as option (option.id)}
          <button
            type="button"
            class="activity-choice"
            aria-pressed={selectedActivity === option.id}
            onclick={() => (selectedActivity = option.id)}
          >
            <span class={['activity-icon', option.id]} aria-hidden="true">
              {#if option.id === 'working'}
                <i></i><i></i><i></i>
              {:else if option.id === 'waiting'}
                !
              {:else if option.id === 'done'}
                <svg viewBox="0 0 16 16" fill="none"><path d="m4 8 2.6 2.6L12 5" /></svg>
              {/if}
            </span>
            {option.label}
          </button>
        {/each}
      </fieldset>
    </div>

    <div class="activity-description">
      <h2 id="activity-heading">In the loop.<br />Out of your way.</h2>
      <p class="activity-intro">Your pet follows your local coding activity. A glance tells you when work is running, waiting, or ready for review.</p>
      <div class="feature-details">
        <details name="companion-features">
          <summary>Lives in your menu bar <ChevronRight size={18} strokeWidth={1.6} aria-hidden="true" /></summary>
          <p>A tiny companion, always close by. Hover for task summaries, or click to choose a pet and adjust its appearance.</p>
        </details>
        <details name="companion-features">
          <summary>Runs locally on your Mac <ChevronRight size={18} strokeWidth={1.6} aria-hidden="true" /></summary>
          <p>Activity stays on your Mac. Optional hooks bring richer reactions to local Codex, Claude Code, and Cursor sessions.</p>
        </details>
        <details name="companion-features">
          <summary>Make it your own <ChevronRight size={18} strokeWidth={1.6} aria-hidden="true" /></summary>
          <p>Follow your selected Codex pet or add a custom companion. <a href="https://github.com/andytyler/codex-pet-bar/blob/main/docs/custom-pets.md" target="_blank" rel="noreferrer">Explore custom pets <ArrowUpRight size={14} aria-hidden="true" /></a></p>
        </details>
      </div>
    </div>
  </div>
</section>

<style>
  .companions, .activity-section { color: #243d32; scroll-margin-top: 40px; }
  .companions { background: #f7f5ed; padding: 38px 6.7vw 24px; }
  .section-inner { max-width: 1328px; margin-inline: auto; }
  .picker-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 32px; }
  h2 { font: 400 52px/1.03 Georgia, 'Times New Roman', serif; letter-spacing: -2px; margin: 0; }
  .picker-heading p { font-size: 17px; line-height: 1.5; margin: 0; }
  fieldset { min-width: 0; border: 0; padding: 0; margin: 0; }
  .pet-picker { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 22px; padding-top: 18px; }
  button { font: inherit; color: inherit; cursor: pointer; }
  .pet-choice { position: relative; display: flex; flex-direction: column; align-items: center; gap: 0; padding: 0 8px 20px; background: transparent; border: 0; border-bottom: 1px solid #dcded0; }
  .pet-choice::after { position: absolute; bottom: -1px; left: 15%; right: 15%; content: ''; height: 3px; border-radius: 2px; background: #4c6a35; transform: scaleX(0); transition: transform 180ms ease; }
  .pet-choice[aria-pressed='true']::after { transform: scaleX(1); }
  .pet-choice:hover::after { transform: scaleX(.55); }
  .pet-choice[aria-pressed='true']:hover::after { transform: scaleX(1); }
  .picker-sprite { display: grid; place-items: center; height: 110px; transition: transform 180ms ease; }
  .pet-choice:hover .picker-sprite { transform: translateY(-5px); }
  .pet-name { font-size: 17px; line-height: 1.4; font-weight: 500; }
  button:focus-visible, summary:focus-visible, a:focus-visible { outline: 2px solid #426e37; outline-offset: 5px; border-radius: 3px; }
  .activity-section { background: #e8eddf; padding: 48px 6.7vw 50px; }
  .activity-layout { display: grid; grid-template-columns: 1.18fr 1fr; align-items: center; column-gap: 11.5%; }
  .preview-label { margin: 0 0 10px; font-size: 11px; letter-spacing: .1em; text-transform: uppercase; color: #5d6d58; display: flex; justify-content: space-between; }

  .sample-window { overflow: hidden; border: 1px solid #c4cbbb; border-radius: 13px; background: #fbfaf4; box-shadow: 0 13px 23px -17px #273b254d; }
  .sample-menubar { display: flex; align-items: center; gap: 27px; min-height: 72px; padding: 7px 22px; border-bottom: 1px solid #dfdfd4; font-size: 15px; }
  .window-controls { display: flex; gap: 7px; margin-right: 8px; }
  .window-controls i { display: block; width: 11px; height: 11px; border-radius: 50%; background: #f37e64; border: 1px solid #e66950; }
  .window-controls i:nth-child(2) { background: #eec05b; border-color: #d9a63b; }
  .window-controls i:nth-child(3) { background: #8aac70; border-color: #749656; }
  .sample-menubar strong { font-weight: 600; }
  .menubar-pet { margin-left: auto; height: 41px; }
  .sample-content { display: flex; align-items: center; min-height: 140px; gap: 24px; padding: 15px 28px; }
  .sample-copy p { margin: 0 0 6px; font-size: 19px; line-height: 1.4; }
  .sample-copy > span { color: #778070; font-size: 12px; }
  .activity-controls { display: grid; grid-template-columns: repeat(4, 1fr); margin-top: 20px; padding: 3px; border: 1px solid #cbd0c0; border-radius: 11px; background: #fbfaf4; }
  .activity-choice { display: flex; justify-content: center; align-items: center; gap: 8px; min-height: 41px; padding: 7px 5px; background: transparent; border: 1px solid transparent; border-radius: 7px; font-size: 16px; white-space: nowrap; transition: background 150ms ease, border-color 150ms ease; }
  .activity-choice:hover { background: #edf0e3; }
  .activity-choice[aria-pressed='true'] { background: #eaf0db; border-color: #69834d; }
  .activity-icon { width: 17px; height: 17px; flex: 0 0 17px; display: flex; align-items: center; justify-content: center; font: 600 12px/1 Arial, sans-serif; }
  .activity-icon.idle { border-radius: 50%; background: #a9ae9f; }
  .activity-icon.working { gap: 2px; }
  .activity-icon.working i { display: block; width: 4px; height: 4px; flex: 0 0 4px; border-radius: 50%; background: #5b7b38; }
  .activity-icon.waiting { border-radius: 50%; background: #dba63a; color: #fff; }
  .activity-icon.done { border-radius: 50%; background: #688c4b; }
  .activity-icon svg { display: block; width: 15px; height: 15px; stroke: #fff; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .activity-description h2 { font-size: 49px; line-height: 1.04; }
  .activity-intro { font-size: 17px; line-height: 1.55; margin: 14px 0 13px; max-width: 420px; }
  .feature-details { border-top: 1px solid #b8c1a4; }
  details { border-bottom: 1px solid #b8c1a4; }
  details:last-child { border-bottom: 0; }
  summary { display: flex; justify-content: space-between; align-items: center; gap: 12px; min-height: 42px; font-size: 17px; list-style: none; cursor: pointer; }
  summary::-webkit-details-marker { display: none; }
  summary :global(svg) { transition: transform 150ms ease; }
  details[open] summary :global(svg) { transform: rotate(90deg); }
  details p { margin: 0 0 14px; max-width: 420px; font-size: 13px; line-height: 1.65; color: #53644d; }
  details a { display: inline-flex; align-items: center; gap: 3px; color: #314f29; text-decoration: underline; text-underline-offset: 3px; }
  .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0; }

  @media (min-width: 1440px) {
    .companions { padding-top: 46px; padding-bottom: 26px; }
    .pet-picker { padding-top: 23px; }
    .pet-choice { padding-bottom: 24px; }
    .activity-section { padding-top: 51px; padding-bottom: 53px; }
  }
  @media (max-width: 1100px) {
    h2 { font-size: 43px; letter-spacing: -1.6px; }
    .picker-heading p { font-size: 14px; max-width: 235px; }
    .activity-layout { column-gap: 7%; grid-template-columns: 1.15fr 1fr; }
    .activity-description h2 { font-size: 42px; }
    .activity-intro { font-size: 15px; }
    .sample-menubar { gap: 20px; padding-inline: 15px; }
    .sample-content { gap: 10px; padding-inline: 15px; }
    .sample-copy p { font-size: 17px; }
    .sample-copy > span { font-size: 10px; }
    .activity-choice { font-size: 12px; gap: 5px; }
  }
  @media (max-width: 760px) {
    .companions { padding: 36px 6.7vw 30px; }
    .picker-heading { display: block; }
    h2 { font-size: 38px; letter-spacing: -1.4px; }
    .picker-heading p { max-width: none; margin-top: 10px; font-size: 14px; }
    .pet-picker { grid-template-columns: repeat(3, minmax(0, 1fr)); column-gap: 15px; row-gap: 13px; padding-top: 20px; }
    .pet-choice { padding-bottom: 12px; }
    .picker-sprite { height: 105px; }
    .pet-name { font-size: 15px; }
    .activity-section { padding: 38px 6.7vw 35px; }
    .activity-layout { grid-template-columns: 1fr; gap: 34px; }
    .activity-description { max-width: none; }
    .activity-description h2 { font-size: 42px; }
    .activity-intro { font-size: 16px; max-width: none; }
    .sample-menubar { gap: 24px; padding-inline: 18px; }
    .sample-content { min-height: 132px; gap: 22px; padding: 16px 22px; }
    .sample-copy p { font-size: 18px; }
    .sample-copy > span { font-size: 11px; }
    .activity-controls { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 3px; margin-top: 14px; }
    .activity-choice { font-size: 14px; min-height: 40px; gap: 8px; }
    summary { min-height: 43px; font-size: 15px; }
    details p { max-width: none; }
  }
  @media (max-width: 370px) {
    h2 { font-size: 34px; }
    .sample-menubar { gap: 17px; }
    .sample-content { gap: 10px; padding-inline: 14px; }
    .sample-copy p { font-size: 16px; }
  }
  @media (prefers-reduced-motion: reduce) {
    .pet-choice::after, .picker-sprite, .activity-choice, summary :global(svg) { transition: none; }
    .pet-choice:hover .picker-sprite { transform: none; }
  }
</style>

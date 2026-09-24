<script lang="ts">
  import type { Attachment } from "svelte/attachments";
  import { prefersReducedMotion } from "svelte/motion";

  // A thin rail of pets running across its container.
  // Each pet's translation speed is locked to the sprite walk-cycle:
  //   ground per sprite frame = --pet-px-per-frame  (default 5px)
  //   frame duration           = --pet-frame-ms     (default 120ms)
  // → linear speed ≈ 41.6 px/s, so feet land in time with the legs.
  //
  // Sprite atlas: 8 cols × 9 rows of 192×208 cells.
  //   row 1 = runningRight (8 frames)
  //   row 2 = runningLeft  (8 frames)

  type Runner = {
    src: string;
    dir?: "right" | "left";
    /** Phase offset along the cycle, 0..1. Defaults to evenly distributed. */
    delayPct?: number;
  };

  type Props = {
    pets: Runner[];
    /** Strip height in px. Pet height = height - 4. Default 32. */
    height?: number;
    /** "light" matches the beige window chrome, "dark" matches the terminal. */
    variant?: "light" | "dark";
    /** Show top + bottom hairline borders. Default true. */
    bordered?: boolean;
    /** Pause and release sprite backgrounds while the host page is inactive. */
    active?: boolean;
    /** ARIA label. */
    label?: string;
  };

  let { pets, height = 32, variant = "light", bordered = true, active = true, label }: Props = $props();

  // Frame-locked speed: 5px per 120ms = 41.67 px/s.
  const PX_PER_FRAME = 5;
  const FRAME_MS = 120;
  const FRAMES = 8;
  const SPEED_PX_PER_S = (PX_PER_FRAME * 1000) / FRAME_MS;
  const CYCLE_S = (FRAMES * FRAME_MS) / 1000;

  let width = $state(0);
  let inViewport = $state(false);

  const observeViewport: Attachment<HTMLDivElement> = (element) => {
    if (typeof IntersectionObserver === "undefined") {
      inViewport = true;
      return;
    }

    const observer = new IntersectionObserver(([entry]) => {
      inViewport = entry?.isIntersecting ?? false;
    }, { rootMargin: "128px 0px" });
    observer.observe(element);
    return () => observer.disconnect();
  };

  // Traversal: pet covers (strip width + 2× overhang) so it enters and exits off-screen.
  // Duration is derived so feet line up with translation at the locked speed.
  const overhang = 40;
  const travelPx = $derived(Math.max(120, width + overhang * 2));
  const durationS = $derived(travelPx / SPEED_PX_PER_S);

  // Spread delays evenly across the traversal so pets are not bunched.
  const runners = $derived(
    pets.map((p, i) => ({
      src: p.src,
      dir: p.dir ?? (i % 2 === 0 ? "right" : "left"),
      delayS: -((p.delayPct ?? i / pets.length) * durationS),
    })),
  );

  const petHeight = $derived(height - 4);
  const petWidth = $derived(Math.round((petHeight * 192) / 208));
  const shouldRender = $derived(active && inViewport && !prefersReducedMotion.current);
</script>

<div
  bind:clientWidth={width}
  {@attach observeViewport}
  class={["strip", `strip-${variant}`, { bordered }]}
  style:--h="{height}px"
  style:--pet-w="{petWidth}px"
  style:--pet-h="{petHeight}px"
  style:--cycle="{CYCLE_S}s"
  style:--dur="{durationS}s"
  style:--travel="{travelPx}px"
  style:--overhang="{overhang}px"
  aria-label={label}
  aria-hidden={label ? undefined : true}
  role={label ? "presentation" : undefined}
>
  {#if shouldRender}
    {#each runners as r (r.src + r.delayS)}
      <span
        class="runner runner-{r.dir}"
        style:--pet={`url(${r.src})`}
        style:--delay="{r.delayS}s"
      ></span>
    {/each}
  {/if}
</div>

<style>
  .strip {
    position: relative;
    height: var(--h);
    overflow: hidden;
    pointer-events: none;
  }
  .strip-light { background: var(--window-2, #efece4); }
  .strip-dark  { background: #1f1c16; }
  .strip.bordered.strip-light { border-bottom: 1.5px solid var(--ink, #1a1814); }
  .strip.bordered.strip-dark  { border-bottom: 1.5px solid #2a2620; }

  .runner {
    position: absolute;
    top: calc((var(--h) - var(--pet-h)) / 2);
    left: 0;
    width: var(--pet-w);
    height: var(--pet-h);
    background-image: var(--pet);
    background-repeat: no-repeat;
    /* Sprite scaled so each cell == (pet-w × pet-h). 8 cols × 9 rows. */
    background-size: calc(var(--pet-w) * 8) calc(var(--pet-h) * 9);
    image-rendering: pixelated;
    will-change: transform, background-position;
  }
  .runner-right {
    background-position: 0 calc(var(--pet-h) * -1);
    animation:
      frmR var(--cycle) steps(8) infinite var(--delay),
      acrR var(--dur)  linear   infinite var(--delay);
  }
  .runner-left {
    background-position: 0 calc(var(--pet-h) * -2);
    animation:
      frmL var(--cycle) steps(8) infinite var(--delay),
      acrL var(--dur)  linear   infinite var(--delay);
  }
  @keyframes frmR {
    from { background-position:                          0  calc(var(--pet-h) * -1); }
    to   { background-position: calc(var(--pet-w) * -8) calc(var(--pet-h) * -1); }
  }
  @keyframes frmL {
    from { background-position:                          0  calc(var(--pet-h) * -2); }
    to   { background-position: calc(var(--pet-w) * -8) calc(var(--pet-h) * -2); }
  }
  @keyframes acrR {
    from { transform: translateX(calc(var(--overhang) * -1)); }
    to   { transform: translateX(calc(var(--travel) - var(--overhang))); }
  }
  @keyframes acrL {
    from { transform: translateX(calc(var(--travel) - var(--overhang))); }
    to   { transform: translateX(calc(var(--overhang) * -1)); }
  }
  @media (prefers-reduced-motion: reduce) {
    .runner { display: none; }
  }
</style>

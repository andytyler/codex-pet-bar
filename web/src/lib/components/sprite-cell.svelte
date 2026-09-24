<script lang="ts" module>
  // Animation rows in the 8×9 pet atlas. Order matches PetAtlasMetadata.
  // Each entry = [row, frameCount, totalMs].
  export const STATES = {
    idle:         [0, 6, 1100],
    runningRight: [1, 8, 1060],
    runningLeft:  [2, 8, 1060],
    waving:       [3, 4,  700],
    jumping:      [4, 5,  840],
    failed:       [5, 8, 1220],
    waiting:      [6, 6, 1010],
    running:      [7, 6,  820],
    review:       [8, 6, 1030],
  } as const;
  export type SpriteState = keyof typeof STATES;
</script>

<script lang="ts">
  import type { Attachment } from "svelte/attachments";

  type Props = {
    src: string;
    state?: SpriteState;
    /** Rendered size in px. Cell aspect 192:208 is preserved on height. */
    size?: number;
    /** Phase offset 0..1 to desync multiple cells. */
    phase?: number;
    /** Pause and release the atlas background while the host page is inactive. */
    active?: boolean;
  };
  let { src, state: spriteState = "idle", size = 64, phase = 0, active = true }: Props = $props();

  let inViewport = $state(false);

  const observeViewport: Attachment<HTMLSpanElement> = (element) => {
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

  const meta    = $derived(STATES[spriteState]);
  const row     = $derived(meta[0]);
  const frames  = $derived(meta[1]);
  const totalMs = $derived(meta[2]);
  const w       = $derived(size);
  const h       = $derived(Math.round((size * 208) / 192));
  const delayMs = $derived(-Math.round(phase * totalMs));
  const shouldLoad = $derived(active && inViewport);
  const backgroundImage = $derived(shouldLoad ? `url(${src})` : "none");
</script>

<span
  {@attach observeViewport}
  class={["cell", { inactive: !shouldLoad }]}
  style:--pet={backgroundImage}
  style:--w="{w}px"
  style:--h="{h}px"
  style:--row={row}
  style:--frames={frames}
  style:--dur="{totalMs}ms"
  style:--delay="{delayMs}ms"
  aria-hidden="true"
></span>

<style>
  .cell {
    display: inline-block;
    width: var(--w);
    height: var(--h);
    background-image: var(--pet);
    background-repeat: no-repeat;
    /* 8 cols × 9 rows scaled so one cell == (w × h). */
    background-size: calc(var(--w) * 8) calc(var(--h) * 9);
    background-position: 0 calc(var(--h) * -1 * var(--row));
    image-rendering: pixelated;
    animation: cell-step var(--dur) steps(var(--frames)) infinite var(--delay);
  }
  .cell.inactive { animation-play-state: paused; }
  @keyframes cell-step {
    from { background-position:                                     0  calc(var(--h) * -1 * var(--row)); }
    to   { background-position: calc(var(--w) * -1 * var(--frames)) calc(var(--h) * -1 * var(--row)); }
  }
  @media (prefers-reduced-motion: reduce) {
    .cell { animation: none; }
  }
</style>

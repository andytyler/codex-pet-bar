<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLAttributes } from "svelte/elements";

  type Star = {
    id: number;
    x: number;
    y: number;
    endX: number;
    endY: number;
    size: number;
    delay: number;
    duration: number;
    rotation: number;
    color: string;
  };

  type StarBurstProps = HTMLAttributes<HTMLDivElement> & {
    children: Snippet;
    disabled?: boolean;
  };

  const stars: Star[] = [
    { id: 1, x: -118, y: -54, endX: -132, endY: -60, size: 9, delay: 0, duration: 760, rotation: -112, color: "#facc15" },
    { id: 2, x: -86, y: -98, endX: -96, endY: -110, size: 6, delay: 30, duration: 700, rotation: 42, color: "#fde68a" },
    { id: 3, x: -55, y: -76, endX: -62, endY: -85, size: 15, delay: 70, duration: 820, rotation: -36, color: "#f59e0b" },
    { id: 4, x: -26, y: -116, endX: -29, endY: -130, size: 7, delay: 20, duration: 780, rotation: 128, color: "#FFD943" },
    { id: 5, x: 7, y: -92, endX: 8, endY: -103, size: 10, delay: 100, duration: 720, rotation: -74, color: "#fbbf24" },
    { id: 6, x: 36, y: -126, endX: 40, endY: -141, size: 6, delay: 55, duration: 850, rotation: 94, color: "#fde047" },
    { id: 7, x: 68, y: -79, endX: 76, endY: -88, size: 12, delay: 15, duration: 790, rotation: -142, color: "#facc15" },
    { id: 8, x: 102, y: -104, endX: 114, endY: -116, size: 7, delay: 85, duration: 760, rotation: 66, color: "#fef08a" },
    { id: 9, x: 128, y: -45, endX: 143, endY: -50, size: 15, delay: 45, duration: 810, rotation: -18, color: "#f59e0b" },
    { id: 10, x: -103, y: -9, endX: -115, endY: -10, size: 5, delay: 120, duration: 690, rotation: 154, color: "#fde68a" },
    { id: 11, x: -61, y: -25, endX: -68, endY: -28, size: 7, delay: 145, duration: 740, rotation: -94, color: "#FFCF0F" },
    { id: 12, x: 55, y: -22, endX: 62, endY: -25, size: 6, delay: 130, duration: 710, rotation: 116, color: "#fbbf24" },
    { id: 13, x: 96, y: -4, endX: 108, endY: -4, size: 15, delay: 105, duration: 760, rotation: -64, color: "#fde047" },
    { id: 14, x: -16, y: -50, endX: -18, endY: -56, size: 5, delay: 165, duration: 650, rotation: 80, color: "#FFA83E" },
    { id: 15, x: 18, y: -58, endX: 20, endY: -65, size: 5, delay: 185, duration: 670, rotation: -126, color: "#FFDB4A" },
    { id: 16, x: 0, y: -137, endX: 0, endY: -153, size: 8, delay: 5, duration: 840, rotation: 180, color: "#fef08a" },
  ];

  let { children, class: className = "", disabled = false, ...restProps }: StarBurstProps = $props();
</script>

<div class={["star-burst", className].filter(Boolean).join(" ")} data-disabled={disabled} {...restProps}>
  <div class="star-burst__stars" aria-hidden="true">
    {#each stars as star (star.id)}
      <span
        class="star-burst__star"
        style={`--star-x: ${star.x}px; --star-y: ${star.y}px; --star-end-x: ${star.endX}px; --star-end-y: ${star.endY}px; --star-size: ${star.size}px; --star-delay: ${star.delay}ms; --star-duration: ${star.duration}ms; --star-rotation: ${star.rotation}deg; --star-color: ${star.color};`}
      ></span>
    {/each}
  </div>

  {@render children()}
</div>

<style>
  .star-burst {
    position: relative;
    display: inline-block;
    overflow: visible;
    isolation: isolate;
    vertical-align: inherit;
  }

  .star-burst__stars {
    position: absolute;
    inset: 0;
    z-index: 2;
    overflow: visible;
    pointer-events: none;
  }

  .star-burst__star {
    position: absolute;
    top: 0;
    left: 50%;
    width: var(--star-size);
    aspect-ratio: 1;
    opacity: 0;
    background: var(--star-color);
    clip-path: polygon(50% 0%, 61% 34%, 98% 35%, 68% 56%, 79% 91%, 50% 70%, 21% 91%, 32% 56%, 2% 35%, 39% 34%);
    filter: drop-shadow(0 2px 4px rgb(245 158 11 / 0.3));
    transform: translate(-50%, -50%) scale(0.3) rotate(0deg);
    transform-origin: center;
  }

  .star-burst:hover:not([data-disabled="true"]) .star-burst__star,
  .star-burst:focus-within:not([data-disabled="true"]) .star-burst__star {
    animation: star-burst-fly var(--star-duration) cubic-bezier(0.16, 1, 0.3, 1) var(--star-delay) both;
  }

  @keyframes star-burst-fly {
    0% {
      opacity: 0;
      transform: translate(-50%, -50%) scale(0.25) rotate(0deg);
    }

    12% {
      opacity: 1;
    }

    68% {
      opacity: 0.95;
      transform: translate(calc(-50% + var(--star-x)), calc(-50% + var(--star-y))) scale(1) rotate(var(--star-rotation));
    }

    100% {
      opacity: 0;
      transform: translate(calc(-50% + var(--star-end-x)), calc(-50% + var(--star-end-y))) scale(0.15) rotate(calc(var(--star-rotation) + 80deg));
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .star-burst:hover:not([data-disabled="true"]) .star-burst__star,
    .star-burst:focus-within:not([data-disabled="true"]) .star-burst__star {
      animation-duration: 1ms;
      animation-delay: 0ms;
    }
  }
</style>

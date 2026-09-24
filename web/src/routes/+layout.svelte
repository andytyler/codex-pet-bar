<script lang="ts">
  import "./layout.css";
  import { base } from "$app/paths";

  let { children } = $props();
</script>

<svelte:head>
  <link rel="icon" type="image/png" sizes="64x64" href={`${base}/favicon.png`} />
  <meta property="og:site_name" content="Codex Pet Bar" />
  <meta property="og:type" content="website" />
  <meta name="twitter:card" content="summary_large_image" />
</svelte:head>
{@render children()}

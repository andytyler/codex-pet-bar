<script lang="ts">
  import Download from "$lib/components/movingicons/download.svelte";
  import StarBurst from "$lib/components/star-burst.svelte";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardAction, CardContent, CardHeader } from "$lib/components/ui/card";
  import { Separator } from "$lib/components/ui/separator";
  import { Tabs, TabsContent, TabsList, TabsTrigger } from "$lib/components/ui/tabs";
  import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "$lib/components/ui/tooltip";
  import { Check, Copy } from "@lucide/svelte";
  import { onMount } from "svelte";

  type InstallMethod = "brew" | "source";

  const brewInstallCommand = "brew install --cask andytyler/tap/codex-pet-bar";
  const sourceInstallCommand = "git clone https://github.com/andytyler/codex-pet-bar.git\ncd codex-pet-bar\n./script/install.sh";
  const brewInstallSteps = brewInstallCommand.split("\n");
  const sourceInstallSteps = sourceInstallCommand.split("\n");

  let isScrolled = $state(false);
  let animate = $state(false);
  let selectedInstallMethod = $state<InstallMethod>("brew");
  let copiedInstallCommand = $state(false);
  let copyResetTimeout: ReturnType<typeof setTimeout> | undefined;
  const selectedInstallCommand = $derived(selectedInstallMethod === "brew" ? brewInstallCommand : sourceInstallCommand);

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
    const copied = await writeClipboardText(selectedInstallCommand);
    if (!copied) {
      copiedInstallCommand = false;
      return;
    }

    copiedInstallCommand = true;

    if (copyResetTimeout) {
      clearTimeout(copyResetTimeout);
    }

    copyResetTimeout = setTimeout(() => {
      copiedInstallCommand = false;
    }, 1800);
  };

  onMount(() => {
    const updateNavState = () => {
      isScrolled = window.scrollY > 24;
    };

    updateNavState();
    window.addEventListener("scroll", updateNavState, { passive: true });

    return () => {
      window.removeEventListener("scroll", updateNavState);
      if (copyResetTimeout) {
        clearTimeout(copyResetTimeout);
      }
    };
  });
</script>

<svelte:head>
  <title>Codex Pet Bar - menu bar pets for Codex</title>
  <meta
    name="description"
    content="A macOS menu bar companion for Codex pets, local hooks, approvals, thread helpers, and custom sprites." />
  <meta property="og:title" content="Codex Pet Bar" />
  <meta property="og:description" content="A macOS menu bar companion for Codex pets, local hooks, approvals, thread helpers, and custom sprites." />
  <meta property="og:image" content="/artwork/open-graph/codex-pet-bar-og-clean-hero.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:alt" content="Codex Pet Bar social card showing tiny menu-bar companion pets beside the product title." />
  <meta name="twitter:title" content="Codex Pet Bar" />
  <meta name="twitter:description" content="A macOS menu bar companion for Codex pets, local hooks, approvals, thread helpers, and custom sprites." />
  <meta name="twitter:image" content="/artwork/open-graph/codex-pet-bar-og-clean-hero.png" />
  <meta name="twitter:image:alt" content="Codex Pet Bar social card showing tiny menu-bar companion pets beside the product title." />
</svelte:head>

<main class="min-h-screen overflow-hidden text-foreground">
  <nav class="fixed inset-x-0 z-40 transition-all duration-500 ease-out top-4 px-4 sm:px-6 lg:px-8" aria-label="Primary">
    <div
      class={` flex w-full items-center justify-between m-2 mx-auto gap-6 border px-4 backdrop-blur-xl ring-1 border-white/40 bg-white/75 rounded-full ring-border transition-all duration-500 ease-out supports-backdrop-filter:bg-white/55 sm:px-5 ${
        isScrolled ? "h-14 max-w-full" : "h-16 max-w-6xl"
      }`}>
      <a class="flex items-center gap-3 text-sm font-bold tracking-tight" href="#top" aria-label="Codex Pet Bar home">
        <enhanced:img src="../lib/assets/goblin-peering-unboxed.png?w=40;80" sizes="40px" alt="" class="size-10 object-cover" />
        <span class="text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          >Codex Pet Bar</span>
      </a>
      <div class="hidden items-center gap-6 text-sm font-medium text-foreground md:flex">
        <a
          class="hover:text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          href="#install">Install</a>
        <a
          class="hover:text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          href="#hooks">Hooks</a>
        <a
          class="hover:text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          href="#features">Use it</a>
        <a
          class="flex items-center hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none hover:opacity-80"
          href="https://github.com/andytyler/codex-pet-bar"
          target="_blank"
          rel="noreferrer">
          <img
            src="https://img.shields.io/github/stars/andytyler/codex-pet-bar?style=social"
            alt="GitHub stars for andytyler/codex-pet-bar"
            class="h-5 w-auto" />
        </a>

        <a
          class="flex items-center gap-2 hover:text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          href="https://ajt.dev"
          target="_blank"
          rel="noreferrer">
          <img src="https://ajt.dev/favicon.png" alt="" class="size-4 rounded object-cover" />
          <span class="text-sm font-semibold text-foreground">ajt.dev</span></a>
      </div>
    </div>
  </nav>

  <div class="absolute -z-20 inset-0 top-0 left-0 w-full h-full bg-linear-to-b from-blue-700 to-transparent opacity-50 backdrop-blur-xl">
    <div class="absolute -z-30 top-0 right-0 w-2/3 h-2/3 bg-radial from-accent to-transparent opacity-80 blur-3xl"></div>
    <div class="absolute -z-30 top-0 right-0 w-1/3 h-1/3 bg-radial from-accent to-transparent opacity-80 blur-3xl"></div>
  </div>
  <section id="top" class="px-4 sm:px-6 sm:pt-18 lg:px-8 lg:pt-20 relative mt-30">
    <div class="mx-auto max-w-7xl">
      <div class="mx-auto max-w-4xl text-center">
        <Badge variant="outline" class="text-sm border-border bg-card font-semibold p-3 px-4 mb-8 text-card-foreground drop-shadow-sm">
          <span class="pr-1">macOS menu bar companion for </span>
          <!-- <img src={codexLogo} alt="Codex logo" class="size-5 inline-block" /> -->
          <enhanced:img src="../lib/assets/codex-outline.png?w=16;20;32;40" sizes="20px" alt="Codex outline" class="size-5 invert dark:invert-0" />
          <span class="">Codex</span></Badge>
        <h1 class="mt-5 text-balance text-5xl font-bold font-sans sm:text-6xl lg:text-7xl">Codex Pet Bar</h1>
        <p class="mx-auto mt-5 max-w-2xl text-balance text-sm text-foreground/80 sm:text-md">
          Tiny pets that listen to local Codex activity, react to approvals, and make each thread easier to read at a glance.
        </p>
        <div class="my-18 flex flex-wrap justify-center gap-x-6 gap-y-3 text-sm font-bold">
          <Button
            onmouseenter={() => (animate = true)}
            onmouseleave={() => (animate = false)}
            variant="default"
            size="lg"
            class="items-center justify-center gap-2 flex px-4 relative group"
            href="#install">
            <enhanced:img
              src="../lib/assets/goblin-peering.png?w=40;80;160"
              sizes="40px"
              alt=""
              class="size-10 -z-10 object-cover absolute top-0 left-10 group-hover:-top-8 transition-all duration-300 ease-in-out opacity-100 group-hover:opacity-100 group-hover:z-10" />
            <Download {animate} size={34} class="font-bold" />
            <span class="text-sm font-semibold">Install from source</span>
          </Button>
          <StarBurst>
            <Button
              variant="ghost"
              size="lg"
              class="items-center justify-center gap-2 flex"
              href="https://github.com/andytyler/codex-pet-bar"
              target="_blank"
              rel="noreferrer">
              <img src="https://github.com/favicon.ico" alt="GitHub stars for andytyler/codex-pet-bar" class="size-5" />
              <span class="text-sm font-semibold">Star us on GitHub</span>
            </Button>
          </StarBurst>
        </div>

        <div class="mx-auto h-full mt-0 w-full max-w-[1080px] pb-10 relative">
          <enhanced:img
            src="../lib/assets/hero.png?w=540;768;1080;1620;2160"
            sizes="min(1080px, 100vw)"
            fetchpriority="high"
            loading="eager"
            alt="A centered transparent lineup of Codex Pet Bar pet characters sitting on a menu bar."
            class="object-contain drop-shadow-[0_24px_36px_rgba(15,23,42,0.18)]" />
          <div class="absolute bottom-21 inset-0 z-20 w-full mx-auto flex justify-center items-end"></div>
        </div>
      </div>

      <div class="absolute -z-10 border-b-4 bottom-25 left-0 w-full border-black/50 blur-sm"></div>
      <div class="absolute -z-10 bottom-25 left-0 w-full h-80 bg-linear-to-t from-primary invert to-transparent opacity-40"></div>
    </div>
  </section>

  <section id="install" class="scroll-mt-28 px-4 py-16 sm:px-6 lg:px-8">
    <div class="mx-auto max-w-5xl">
      <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="font-mono text-xs font-bold uppercase tracking-[0.2em] text-blue-700">Installation</p>
          <h2 class="mt-2 text-2xl font-black tracking-normal sm:text-3xl">Install Codex Pet Bar</h2>
        </div>
        <p class="max-w-sm text-sm font-medium leading-6 text-zinc-600 sm:text-right">Install with Homebrew, or clone the repository and run the macOS installer locally.</p>
      </div>

      <Card
        data-testid="install-code-box"
        class="gap-0 overflow-hidden rounded-[22px] border border-zinc-200/90 bg-white/92 py-0 shadow-[0_20px_54px_rgba(15,23,42,0.10)] ring-1 ring-white/70">
        <TooltipProvider>
          <Tabs bind:value={selectedInstallMethod} class="gap-0">
            <CardHeader class="min-h-14 items-center gap-4 rounded-none bg-zinc-100/70 px-5 py-0 sm:px-6">
              <TabsList
                data-testid="install-code-tabs"
                class="min-w-0 rounded-xl border border-zinc-200/80 bg-white/80 p-1 text-sm font-semibold shadow-xs">
                <TabsTrigger
                  data-testid="install-code-tab-brew"
                  value="brew"
                  class="h-8 rounded-lg px-3 text-zinc-600 data-[state=active]:bg-emerald-700 data-[state=active]:text-white data-[state=active]:shadow-sm">
                  Homebrew
                </TabsTrigger>
                <TabsTrigger
                  data-testid="install-code-tab-source"
                  value="source"
                  class="h-8 rounded-lg px-3 text-zinc-600 data-[state=active]:bg-emerald-700 data-[state=active]:text-white data-[state=active]:shadow-sm">
                  Source Code
                </TabsTrigger>
              </TabsList>

              <CardAction class="self-center">
                <Tooltip>
                  <TooltipTrigger>
                    {#snippet child({ props })}
                      <Button
                        {...props}
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        class="text-zinc-500 hover:bg-white hover:text-zinc-950"
                        aria-label={copiedInstallCommand ? "Install command copied" : "Copy install command"}
                        onclick={copyInstallCommand}>
                        {#if copiedInstallCommand}
                          <Check class="text-emerald-700" aria-hidden="true" />
                        {:else}
                          <Copy aria-hidden="true" />
                        {/if}
                      </Button>
                    {/snippet}
                  </TooltipTrigger>
                  <TooltipContent sideOffset={6}>{copiedInstallCommand ? "Copied" : "Copy command"}</TooltipContent>
                </Tooltip>
              </CardAction>
            </CardHeader>

            <Separator />

            <CardContent
              data-testid="install-code-panel"
              class="m-1 overflow-hidden rounded-[18px] bg-white p-0 shadow-[inset_0_0_0_1px_rgba(228,228,231,0.9)]">
              <TabsContent data-testid="install-code-content-brew" value="brew" class="m-0">
                <div class="overflow-x-auto px-5 py-6 font-mono text-[14px] leading-8 text-slate-900 sm:px-7 sm:py-7 sm:text-[15px]">
                  <code class="grid gap-1.5"
                    >{#each brewInstallSteps as command (command)}
                      <span class="grid grid-cols-[auto_minmax(0,1fr)] gap-3"
                        ><span class="select-none text-emerald-700">$</span><span class="min-w-0 whitespace-pre-wrap break-all sm:whitespace-pre sm:break-normal"
                          >{command}</span
                        ></span>
                    {/each}</code>
                </div>
              </TabsContent>

              <TabsContent data-testid="install-code-content-source" value="source" class="m-0">
                <div class="overflow-x-auto px-5 py-6 font-mono text-[14px] leading-8 text-slate-900 sm:px-7 sm:py-7 sm:text-[15px]">
                  <code class="grid gap-1.5"
                    >{#each sourceInstallSteps as command (command)}
                      <span class="grid grid-cols-[auto_minmax(0,1fr)] gap-3"
                        ><span class="select-none text-emerald-700">$</span><span class="min-w-0 whitespace-pre-wrap break-all sm:whitespace-pre sm:break-normal"
                          >{command}</span
                        ></span>
                    {/each}</code>
                </div>
              </TabsContent>
            </CardContent>
          </Tabs>
        </TooltipProvider>
      </Card>
    </div>
  </section>

  <section id="hooks" class="px-4 py-20 sm:px-6 lg:px-8">
    <div class="mx-auto max-w-7xl">
      <div class="mx-auto max-w-3xl text-center">
        <p class="text-sm font-bold uppercase tracking-[0.2em] text-blue-700">Hook reactions</p>
        <h2 class="mt-3 text-3xl font-black tracking-normal sm:text-4xl">A different pet for every kind of moment.</h2>
        <p class="mt-3 text-pretty leading-7 text-zinc-600">
          Codex Pet Bar listens to lifecycle hooks and turns them into a small, readable state change instead of another notification.
        </p>
      </div>

      <div class="mt-14 space-y-16">
        <article class="grid gap-8 lg:grid-cols-[0.75fr_1fr] lg:items-center">
          <img
            src="/artwork/moments/approval-rock.png"
            alt="Rock pet reacting to a Codex permission request."
            class="mx-auto w-full max-w-sm object-contain drop-shadow-[0_20px_28px_rgba(15,23,42,0.18)]" />
          <div>
            <p class="font-mono text-xs font-bold uppercase tracking-[0.18em] text-amber-700">PermissionRequest / permission_requested</p>
            <h3 class="mt-3 text-2xl font-black tracking-normal sm:text-3xl">Approval gets a visible flag.</h3>
            <p class="mt-3 max-w-2xl text-pretty leading-7 text-zinc-600">
              When Codex needs permission, Rock pops into view with the Codex flag so the pause feels deliberate instead of mysterious.
            </p>
          </div>
        </article>

        <article class="grid gap-8 lg:grid-cols-[1fr_0.75fr] lg:items-center">
          <div class="lg:order-2">
            <img
              src="/artwork/moments/running-flame.png"
              alt="Flame pet running while Codex uses tools."
              class="mx-auto w-full max-w-sm object-contain drop-shadow-[0_20px_28px_rgba(15,23,42,0.18)]" />
          </div>
          <div class="lg:order-1">
            <p class="font-mono text-xs font-bold uppercase tracking-[0.18em] text-blue-700">PreToolUse / tool_started</p>
            <h3 class="mt-3 text-2xl font-black tracking-normal sm:text-3xl">Tool runs feel alive.</h3>
            <p class="mt-3 max-w-2xl text-pretty leading-7 text-zinc-600">
              PreToolUse and edit events turn into motion. Flame runs while Codex is changing files, searching, or doing the work.
            </p>
          </div>
        </article>

        <article class="grid gap-8 lg:grid-cols-[0.75fr_1fr] lg:items-center">
          <img
            src="/artwork/moments/completed-ajt.png"
            alt="AJT pet celebrating completed Codex work."
            class="mx-auto w-full max-w-sm object-contain drop-shadow-[0_20px_28px_rgba(15,23,42,0.18)]" />
          <div>
            <p class="font-mono text-xs font-bold uppercase tracking-[0.18em] text-emerald-700">PostToolUse / stopped</p>
            <h3 class="mt-3 text-2xl font-black tracking-normal sm:text-3xl">Completed work gets a finish line.</h3>
            <p class="mt-3 max-w-2xl text-pretty leading-7 text-zinc-600">
              Successful tool results and stops settle the pet back down, with a small celebratory moment when the thread is done.
            </p>
          </div>
        </article>
      </div>
    </div>
  </section>

  <section id="privacy" class="px-4 py-16 sm:px-6 lg:px-8">
    <div id="features" class="mx-auto grid max-w-7xl scroll-mt-28 gap-10 md:grid-cols-2 lg:grid-cols-4">
      <div>
        <h3 class="font-black">Local first</h3>
        <p class="mt-2 text-sm leading-6 text-zinc-600">
          Hooks read local Codex activity and write small status updates under <code class="font-mono">~/.codex</code>.
        </p>
      </div>
      <div>
        <h3 class="font-black">No background cloud</h3>
        <p class="mt-2 text-sm leading-6 text-zinc-600">The app is a macOS menu bar utility, not a hosted service.</p>
      </div>
      <div>
        <h3 class="font-black">Hackable pets</h3>
        <p class="mt-2 text-sm leading-6 text-zinc-600">Custom pet packages live on disk, so you can inspect and replace them.</p>
      </div>
      <div>
        <h3 class="font-black">Open source</h3>
        <p class="mt-2 text-sm leading-6 text-zinc-600">
          Made by <a class="font-semibold text-blue-700 hover:text-blue-600" href="https://ajt.dev" target="_blank" rel="noreferrer">Andy Tyler</a> and published
          for people who want to hack on it.
        </p>
      </div>
    </div>
  </section>

  <footer class="px-4 py-8 mt-20 sm:px-6 lg:px-8 bg-background border-t border-border relative">
    <enhanced:img src="../lib/assets/goblin-peering.png?w=40;80;160" sizes="80px" alt="" class="size-20 object-cover absolute -top-16 left-20" />
    <div class="mx-auto flex max-w-7xl flex-col gap-4 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between relative">
      <p><span class="font-bold text-foreground">Codex Pet Bar</span> is open source, MIT Licence.</p>
      <p>
        <span class="">Made with</span>
        <enhanced:img src="../lib/assets/codex-outline.png?w=16;20;32;40" sizes="16px" alt="Codex outline" class="size-4 inline-block invert dark:invert-0" />
        <span class="">Codex by</span>
        <a class="" href="https://ajt.dev" target="_blank" rel="noreferrer"> Andy Tyler</a>
        <span class="">in 🇬🇧</span>
      </p>
      <div class="flex flex-wrap items-center gap-5 font-semibold">
        <a
          class="flex items-center gap-2 hover:text-foreground hover:underline-offset-4 hover:underline transition-all underline-offset-0 hover:underline-primary underline-none"
          href="https://ajt.dev"
          target="_blank"
          rel="noreferrer">
          <img src="https://ajt.dev/favicon.png" alt="" class="size-4 rounded object-cover" />
          <span class="">ajt.dev</span></a>
        <a class="hover:text-foreground" href="https://github.com/andytyler/codex-pet-bar" target="_blank" rel="noreferrer">GitHub</a>
        <a class="hover:text-foreground" href="#top">Back to top</a>
      </div>
    </div>
  </footer>
</main>

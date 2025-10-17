<script lang="ts">
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import type { AriaRole } from 'svelte/elements';

  interface Props {
    size?: string | number;
    color?: string;
    path: string;
    title?: string | null;
    desc?: string;
    flipped?: boolean;
    class?: string;
    viewBox?: string;
    role?: AriaRole;
    ariaHidden?: boolean | undefined;
    ariaLabel?: string | undefined;
    ariaLabelledby?: string | undefined;
    strokeWidth?: number;
    strokeColor?: string;
    spin?: boolean;
    progress?: number;
  }

  let {
    size = '1em',
    color = 'currentColor',
    path,
    title = null,
    desc = '',
    flipped = false,
    class: className = '',
    viewBox = '0 0 24 24',
    role = 'img',
    ariaHidden = undefined,
    ariaLabel = undefined,
    ariaLabelledby = undefined,
    strokeWidth = 0,
    strokeColor = 'currentColor',
    spin = false,
    progress = undefined,
  }: Props = $props();

  const radius = 10;
  const circumference = 2 * Math.PI * radius;

  const progressOffset = $derived(
    progress === undefined ? circumference : circumference - (progress / 100) * circumference,
  );

  let theme = $derived(themeManager.theme);

  $effect(() => {
    theme = themeManager.theme;
  });
</script>

<svg
  width={size}
  height={size}
  {viewBox}
  class="{className} {flipped ? '-scale-x-100' : ''} {spin ? 'animate-spin' : ''}"
  {role}
  stroke={strokeColor}
  stroke-width={strokeWidth}
  aria-label={ariaLabel}
  aria-hidden={ariaHidden}
  aria-labelledby={ariaLabelledby}
>
  {#if title}
    <title>{title}</title>
  {/if}
  {#if desc}
    <desc>{desc}</desc>
  {/if}
  {#if progress === undefined}
    <path d={path} fill={color} />
  {:else}
    <circle
      cx="12"
      cy="12"
      r={radius}
      fill="none"
      stroke={theme.value === 'light' ? '#E0E0E0' : '#616161'}
      stroke-width={2}
    />
    <circle
      cx="12"
      cy="12"
      r={radius}
      fill="none"
      stroke={theme.value === 'light' ? 'oklch(96.7% 0.003 264.542)' : 'rgb(33 33 33)'}
      stroke-width={6}
      stroke-dasharray={circumference}
      stroke-dashoffset={progressOffset}
      stroke-linecap="round"
      transform="rotate(-90 12 12)"
    />
    <circle
      cx="12"
      cy="12"
      r={radius}
      fill="none"
      stroke={strokeColor}
      stroke-width={2}
      stroke-dasharray={circumference}
      stroke-dashoffset={progressOffset}
      stroke-linecap="round"
      transform="rotate(-90 12 12)"
    />
  {/if}
</svg>

<style>
  svg {
    transition: transform 0.2s ease;
  }
  circle {
    transition: stroke-dashoffset 0.35s ease;
  }
</style>

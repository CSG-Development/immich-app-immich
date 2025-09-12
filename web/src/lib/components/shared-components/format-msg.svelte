<script lang="ts">
  import FormatMessage from '$lib/components/i18n/format-message.svelte';

  let { key, values } = $props<{
    key: string;
    values: Record<string, unknown>;
  }>();
</script>

<FormatMessage {key} {values}>
  {#snippet children({ message })}
    <b>{message}</b>
  {/snippet}
</FormatMessage>

<script lang="ts">
  import ConfirmDialog from '$lib/components/shared-components/dialog/confirm-dialog.svelte';
  import { dialogController } from './dialog';
  const { dialog } = dialogController;
</script>

{#if $dialog}
  <ConfirmDialog {...$dialog} />
{/if}

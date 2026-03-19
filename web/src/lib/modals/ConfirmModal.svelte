<script lang="ts">
  import { Button, HStack, Modal, ModalBody, ModalFooter, type Color } from '@immich/ui';
  import type { Snippet } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props {
    title?: string;
    icon?: string | boolean;
    prompt?: string;
    confirmText?: string;
    confirmColor?: Color;
    disabled?: boolean;
    size?: 'small' | 'medium';
    onClose: (confirmed: boolean) => void;
    promptSnippet?: Snippet;
    mdFullSize?: boolean;
  }

  let {
    title = $t('confirm'),
    icon,
    prompt = $t('prompt_default'),
    confirmText = $t('confirm'),
    confirmColor = 'danger',
    disabled = false,
    size = 'small',
    onClose,
    promptSnippet,
    mdFullSize = true,
  }: Props = $props();

  const handleConfirm = () => {
    onClose(true);
  };
</script>

<Modal {title} onClose={() => onClose(false)} {size} {icon} {mdFullSize}>
  <ModalBody>
    {#if promptSnippet}{@render promptSnippet()}{:else}
      <p>{prompt}</p>
    {/if}
  </ModalBody>

  <ModalFooter>
    <HStack fullWidth>
      <Button
        shape="round"
        color="secondary"
        size="standard-large"
        class="font-normal"
        fullWidth
        onclick={() => onClose(false)}
      >
        {$t('cancel')}
      </Button>
      <Button
        shape="round"
        color={confirmColor}
        size="standard-large"
        class="font-normal"
        fullWidth
        onclick={handleConfirm}
        {disabled}
      >
        {confirmText}
      </Button>
    </HStack>
  </ModalFooter>
</Modal>

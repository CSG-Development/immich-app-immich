<script lang="ts">
  import { searchPluginMethods, WorkflowTrigger, type PluginMethodResponseDto } from '@immich/sdk';
  import { Badge, BasicModal, ListButton, LoadingSpinner, Stack, Text } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  type Props = {
    trigger: WorkflowTrigger;
    selectedKey?: string;
    onClose: (method?: PluginMethodResponseDto) => void;
  };

  const { trigger, selectedKey, onClose }: Props = $props();

  let methods = $state<PluginMethodResponseDto[] | undefined>();
  let error = $state(false);

  onMount(() => {
    void searchPluginMethods({ trigger })
      .then((result) => {
        methods = Array.isArray(result) ? result : [];
      })
      .catch(() => {
        error = true;
        methods = [];
      });
  });
</script>

<BasicModal title={$t('add_step')} onClose={() => onClose()} size="medium">
  {#if methods === undefined}
    <div class="flex w-full place-content-center place-items-center py-8">
      <LoadingSpinner />
    </div>
  {:else if error}
    <Text color="danger" class="py-6 text-center">{$t('errors.something_went_wrong')}</Text>
  {:else if methods.length === 0}
    <Text color="muted" class="py-6 text-center">{$t('no_results')}</Text>
  {:else}
    <Stack>
      {#each methods as method (method.key)}
        <ListButton selected={method.key === selectedKey} onclick={() => onClose(method)}>
          <div class="grow text-start">
            <Text fontWeight="medium" class="flex items-center gap-1">
              {method.title}
              {#if method.uiHints?.includes('Filter')}
                <Badge size="tiny" color="info" title={$t('plugin_method_filter_type_description')}>
                  {$t('plugin_method_filter_type')}
                </Badge>
              {/if}
            </Text>
            {#if method.description}
              <Text size="tiny" color="muted">{method.description}</Text>
            {/if}
          </div>
        </ListButton>
      {/each}
    </Stack>
  {/if}
</BasicModal>

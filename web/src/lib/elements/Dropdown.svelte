<script lang="ts" module>
  // Necessary for eslint
  /* eslint-disable @typescript-eslint/no-explicit-any */
  type T = any;

  export type RenderedOption = {
    title: string;
    icon?: string;
    disabled?: boolean;
  };
</script>

<script lang="ts" generics="T">
  import { clickOutside } from '$lib/actions/click-outside';
  import { Button, Icon, Text } from '@immich/ui';
  import { mdiCheck } from '@mdi/js';
  import { isEqual } from 'lodash-es';
  import { fly } from 'svelte/transition';

  interface Props {
    class?: string;
    options: T[];
    selectedOption?: any;
    showMenu?: boolean;
    controlable?: boolean;
    hideTextOnSmallScreen?: boolean;
    title?: string | undefined;
    position?: 'bottom-left' | 'bottom-right';
    onSelect: (option: T) => void;
    onClickOutside?: () => void;
    onShowMenuChange?: (show: boolean) => void;
    render?: (item: T) => string | RenderedOption;
    isShareModal?: boolean;
  }

  let {
    position = 'bottom-left',
    class: className = '',
    options,
    selectedOption = $bindable(options[0]),
    showMenu = $bindable(false),
    controlable = false,
    hideTextOnSmallScreen = true,
    title = undefined,
    onSelect,
    onClickOutside = () => {},
    onShowMenuChange,
    render = String,
    isShareModal = false,
  }: Props = $props();

  const handleClickOutside = () => {
    if (!controlable) {
      showMenu = false;
    }
    onShowMenuChange?.(showMenu);

    onClickOutside();
  };

  const handleSelectOption = (option: T) => {
    onSelect(option);
    selectedOption = option;

    showMenu = false;
    onShowMenuChange?.(showMenu);
  };

  const renderOption = (option: T): RenderedOption => {
    const renderedOption = render(option);
    switch (typeof renderedOption) {
      case 'string': {
        return { title: renderedOption };
      }
      default: {
        return {
          title: renderedOption.title,
          icon: renderedOption.icon,
          disabled: renderedOption.disabled,
        };
      }
    }
  };

  let renderedSelectedOption = $derived(renderOption(selectedOption));

  const getAlignClass = (position: 'bottom-left' | 'bottom-right') => {
    switch (position) {
      case 'bottom-left': {
        return 'start-0';
      }
      case 'bottom-right': {
        return 'end-0';
      }

      default: {
        return '';
      }
    }
  };

  let button: HTMLDivElement | undefined = $state();

  let menuStyle = $state('');

  $effect(() => {
    if (isShareModal) {
      if (!button || !showMenu) {
        menuStyle = '';
      } else {
        const rect = button.getBoundingClientRect();
        const top = rect.top + window.scrollY;
        const left = position === 'bottom-left' ? rect.left + window.scrollX : rect.right + window.scrollX - 320;
        menuStyle = `position: fixed; top: ${top}px; left: ${left}px; z-index: 1000;`;
      }
    }
  });
</script>

<div
  bind:this={button}
  use:clickOutside={{ onOutclick: handleClickOutside, onEscape: handleClickOutside }}
  class="relative"
>
  <!-- BUTTON TITLE -->
  <Button
    onclick={() => {
      showMenu = !showMenu;
      onShowMenuChange?.(showMenu);
    }}
    fullWidth
    variant="ghost"
    color="primary"
    size="small"
    {title}
    class="gap-2"
  >
    {#if renderedSelectedOption?.icon}
      <Icon icon={renderedSelectedOption.icon} size="24" />
    {/if}
    <Text class={hideTextOnSmallScreen ? 'hidden sm:block font-medium' : 'font-medium'}
      >{renderedSelectedOption.title}</Text
    >
  </Button>

  <!-- DROP DOWN MENU -->
  {#if showMenu}
    <div
      transition:fly={{ y: -30, duration: 250 }}
      style={menuStyle}
      class="flex min-w-[250px] max-h-[70vh] overflow-y-auto immich-scrollbar flex-col rounded-2xl bg-immich-bg-gray-mt text-black shadow-lg
      dark:bg-immich-dark-gray-card dark:text-white {className} {isShareModal
        ? ''
        : `${getAlignClass(position)} z-1 top-0 -right-4 absolute`}"
    >
      {#each options as option (option)}
        {@const renderedOption = renderOption(option)}
        {@const buttonStyle = renderedOption.disabled
          ? ''
          : 'transition-all hover:bg-immich-primary-12 dark:hover:bg-immich-dark-primary-24'}
        <button
          type="button"
          class="grid grid-cols-[24px_1fr] place-items-center py-[15px] px-[18px] gap-4 disabled:opacity-40 {buttonStyle}"
          disabled={renderedOption.disabled}
          onclick={() => !renderedOption.disabled && handleSelectOption(option)}
        >
          {#if isEqual(selectedOption, option)}
            <div class="text-primary">
              <Icon icon={mdiCheck} size="24" />
            </div>
            <p class="justify-self-start text-primary">
              {renderedOption.title}
            </p>
          {:else}
            <div></div>
            <p class="justify-self-start font-normal text-base">
              {renderedOption.title}
            </p>
          {/if}
        </button>
      {/each}
    </div>
  {/if}
</div>

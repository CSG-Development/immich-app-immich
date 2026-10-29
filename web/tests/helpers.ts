import TestWrapper from '$lib/components/TestWrapper.svelte';
import { render, type RenderResult } from '@testing-library/svelte';
import type { Component, ComponentProps } from 'svelte';

// Svelte component props vary by component; a tight bound breaks call sites.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyComponent = Component<any>;

type TooltipRenderResult<C extends AnyComponent> = Omit<RenderResult<C>, 'rerender'> & {
  rerender: (props: Partial<ComponentProps<C>>) => Promise<void>;
};

export const renderWithTooltips = <C extends AnyComponent>(
  component: C,
  props: ComponentProps<C>,
): TooltipRenderResult<C> => {
  const result = render(TestWrapper as Component<{ component: C; componentProps: ComponentProps<C> }>, {
    component,
    componentProps: props,
  });

  return {
    ...(result as unknown as RenderResult<C>),
    rerender: async (nextProps: Partial<ComponentProps<C>>) => {
      await result.rerender({
        component,
        componentProps: { ...props, ...nextProps },
      });
    },
  };
};

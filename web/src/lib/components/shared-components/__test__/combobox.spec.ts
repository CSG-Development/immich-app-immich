import { getIntersectionObserverMock } from '$lib/__mocks__/intersection-observer.mock';
import { getVisualViewportMock } from '$lib/__mocks__/visual-viewport.mock';
import Combobox from '$lib/components/shared-components/Combobox.svelte';
import { renderWithTooltips } from '$tests/helpers';
import { screen } from '@testing-library/svelte';

describe('Combobox component', () => {
  beforeAll(() => {
    vi.stubGlobal('IntersectionObserver', getIntersectionObserverMock());
    vi.stubGlobal('visualViewport', getVisualViewportMock());
  });

  it('shows selected option', () => {
    renderWithTooltips(Combobox, {
      label: 'test',
      selectedOption: { label: 'option-1', value: 'option-1' },
    });

    expect(screen.getByRole('combobox')).toHaveValue('option-1');
  });

  it('clears the selected option when set to undefined', async () => {
    const { rerender } = renderWithTooltips(Combobox, {
      label: 'test',
      selectedOption: { label: 'option-1', value: 'option-1' },
    });

    await rerender({ label: 'test', selectedOption: undefined });
    expect(screen.getByRole('combobox')).toHaveValue('');
  });
});

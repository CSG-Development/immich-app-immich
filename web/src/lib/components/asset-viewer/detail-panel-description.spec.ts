import { eventManager } from '$lib/managers/event-manager.svelte';
import { getAssetInfo, updateAsset } from '@immich/sdk';
import { assetFactory } from '@test-data/factories/asset-factory';
import '@testing-library/jest-dom';
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import DetailPanelDescription from './detail-panel-description.svelte';

vi.mock('@immich/sdk', async () => {
  const sdk = await vi.importActual<typeof import('@immich/sdk')>('@immich/sdk');
  return {
    ...sdk,
    updateAsset: vi.fn(),
    getAssetInfo: vi.fn(),
  };
});

vi.mock('@immich/ui', async () => {
  const { default: MockTextarea } = await import('./__mocks__/textarea-mock.svelte');
  return {
    Textarea: MockTextarea,
    toastManager: {
      primary: vi.fn(),
      danger: vi.fn(),
    },
    shortcut: () => ({}),
    matchesShortcut: () => false,
    shortcutLabel: () => '',
    shortcuts: () => ({}),
    shouldIgnoreEvent: () => false,
  };
});

vi.mock('$lib/actions/shortcut', () => ({
  shortcut: () => ({}),
}));

vi.mock('$lib/utils/handle-error', () => ({
  handleError: vi.fn(),
}));

describe('DetailPanelDescription', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('emits AssetUpdate after saving a description', async () => {
    const emitSpy = vi.spyOn(eventManager, 'emit');
    const asset = assetFactory.build({
      id: 'asset-a',
      exifInfo: { description: '' },
    });
    const updated = {
      ...asset,
      exifInfo: { ...asset.exifInfo, description: 'new description' },
    };

    vi.mocked(updateAsset).mockResolvedValue(updated);
    vi.mocked(getAssetInfo).mockResolvedValue(updated);

    render(DetailPanelDescription, {
      props: {
        asset,
        isOwner: true,
      },
    });

    const textarea = screen.getByTestId('autogrow-textarea') as HTMLTextAreaElement;
    await fireEvent.input(textarea, { target: { value: 'new description' } });
    await fireEvent.focusOut(textarea);

    await waitFor(() =>
      expect(updateAsset).toHaveBeenCalledWith({
        id: asset.id,
        updateAssetDto: { description: 'new description' },
      }),
    );
    await waitFor(() => expect(getAssetInfo).toHaveBeenCalledWith({ id: asset.id }));
    expect(emitSpy).toHaveBeenCalledWith('AssetUpdate', {
      ...updated,
      exifInfo: { ...updated.exifInfo, description: 'new description' },
    });
  });

  it('clears unsaved draft on asset change', async () => {
    const assetA = assetFactory.build({
      id: 'asset-a',
      exifInfo: { description: '' },
    });
    const assetB = assetFactory.build({
      id: 'asset-b',
      exifInfo: { description: '' },
    });

    const { rerender } = render(DetailPanelDescription, {
      props: {
        asset: assetA,
        isOwner: true,
      },
    });

    const textarea = screen.getByTestId('autogrow-textarea') as HTMLTextAreaElement;
    await fireEvent.input(textarea, { target: { value: 'unsaved draft' } });
    expect(textarea).toHaveValue('unsaved draft');

    await rerender({
      asset: assetB,
      isOwner: true,
    });

    expect(screen.getByTestId('autogrow-textarea')).toHaveValue('');
  });

  it('keeps draft when the same asset is replaced with a new object', async () => {
    const assetA = assetFactory.build({
      id: 'asset-a',
      exifInfo: { description: '' },
    });
    const assetARefresh = {
      ...assetA,
      exifInfo: { ...assetA.exifInfo, description: '' },
    };

    const { rerender } = render(DetailPanelDescription, {
      props: {
        asset: assetA,
        isOwner: true,
      },
    });

    const textarea = screen.getByTestId('autogrow-textarea') as HTMLTextAreaElement;
    await fireEvent.input(textarea, { target: { value: '123' } });
    expect(textarea).toHaveValue('123');

    await rerender({
      asset: assetARefresh,
      isOwner: true,
    });

    expect(screen.getByTestId('autogrow-textarea')).toHaveValue('123');
  });

  it('updates description on asset switch', async () => {
    const assetA = assetFactory.build({
      id: 'asset-a',
      exifInfo: { description: 'first description' },
    });
    const assetB = assetFactory.build({
      id: 'asset-b',
      exifInfo: { description: 'second description' },
    });

    const { rerender } = render(DetailPanelDescription, {
      props: {
        asset: assetA,
        isOwner: true,
      },
    });

    expect(screen.getByTestId('autogrow-textarea')).toHaveValue('first description');

    await rerender({
      asset: assetB,
      isOwner: true,
    });

    expect(screen.getByTestId('autogrow-textarea')).toHaveValue('second description');
  });
});

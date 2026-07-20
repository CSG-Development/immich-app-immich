<script lang="ts">
  import { goto } from '$app/navigation';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import UserPageLayout, { headerId } from '$lib/components/layouts/user-page-layout.svelte';
  import Breadcrumbs from '$lib/components/shared-components/tree/breadcrumbs.svelte';
  import TreeItemThumbnails from '$lib/components/shared-components/tree/tree-item-thumbnails.svelte';
  import TreeItems from '$lib/components/shared-components/tree/tree-items.svelte';
  import Sidebar from '$lib/components/sidebar/sidebar.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import { AssetAction } from '$lib/constants';
  import SkipLink from '$lib/elements/SkipLink.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { Route } from '$lib/route';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { getTagActions } from '$lib/services/tag.service';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { joinPaths, TreeNode } from '$lib/utils/tree-utils';
  import { getAllTags, type TagResponseDto } from '@immich/sdk';
  import { ActionButton, CommandPaletteDefaultProvider, ContextMenuButton } from '@immich/ui';
  import { mdiDotsVertical, mdiTag, mdiTagMultiple } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import { locale } from '$lib/stores/preferences.store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  const handleClick = () => {
    if (assetMultiSelectManager.selectedAssets.length > 0) {
      assetMultiSelectManager.clear();
    }
  };

  let tags = $derived<TagResponseDto[]>(data.tags);
  const tree = $derived(TreeNode.fromTags(tags));
  const tag = $derived(tree.traverse(data.path));

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = $derived({ deferInit: !tag, tagId: tag?.id });

  const handleNavigation = (tag: string) => navigateToView(joinPaths(data.path, tag));

  const getLink = (path: string) => Route.tags({ path });

  const navigateToView = (path: string) => goto(getLink(path));

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetMultiSelectManager.clear();
  };

  const onRefresh = async () => {
    tags = await getAllTags();
  };

  const onTagDelete = async (response: TreeNode) => {
    if (response.path === tag.path) {
      await navigateToView(tag.parent ? tag.parent.path : '');
    }

    await onRefresh();
  };

  const { Create, Update, Delete } = $derived(getTagActions($t, tag));

  let pageItemCount = $derived(tag.hasAssets ? (timelineManager?.assetCount ?? 0) : tag.children.length);

  let { slideshowState, slideshowNavigation } = slideshowStore;

  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = () => {
    assetMultiSelectManager.selectedAssets.sort(
      (a, b) => toDate(b.fileCreatedAt).getTime() - toDate(a.fileCreatedAt).getTime(),
    );
    shuffledSelectedAssets = [...assetMultiSelectManager.selectedAssets].sort(() => Math.random() - 0.5);
    const nav = get(slideshowNavigation);
    const asset = getFirstSlideshowAsset(assetMultiSelectManager.selectedAssets, shuffledSelectedAssets, nav);
    if (asset) {
      handlePromiseError(
        assetViewerManager.setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)),
      );
    }
  };

  const menuItems = $derived(
    getAssetSelectMenuItems($t, {
      showSlideshow: true,
      onStartSlideshow: handleStartSlideshow,
      onArchive: (ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility)),
      onVisibilitySet: handleSetVisibility,
      onAssetDelete: (assetIds) => timelineManager.removeAssets(assetIds),
      onUndoDelete: (assets) => timelineManager.upsertAssets(assets),
    }),
  );
</script>

<OnEvents onTagCreate={onRefresh} onTagUpdate={onRefresh} {onTagDelete} />

<UserPageLayout
  title={formatPageTitleWithCount(data.meta.title, pageItemCount, $locale)}
  actions={[Create, Update, Delete]}
>
  {#snippet sidebar()}
    <Sidebar>
      <SkipLink target={`#${headerId}`} text={$t('skip_to_tags')} breakpoint="md" />
      <section>
        <div class="ps-4 pb-3 text-black/60 dark:text-white/70">{$t('explorer').toUpperCase()}</div>
        <div class="h-full">
          <TreeItems icons={{ default: mdiTag, active: mdiTag }} {tree} active={tag.path} {getLink} {handleClick} />
        </div>
      </section>
    </Sidebar>
  {/snippet}

  <Breadcrumbs node={tag} icon={mdiTagMultiple} title={$t('tags')} {getLink} />

  <section class="mt-2 h-[calc(100%-(--spacing(20)))] overflow-auto immich-scrollbar">
    {#if tag.hasAssets}
      <Timeline
        enableRouting={true}
        bind:timelineManager
        {options}
        assetInteraction={assetMultiSelectManager}
        removeAction={AssetAction.UNARCHIVE}
      >
        {#snippet empty()}
          <TreeItemThumbnails items={tag.children} icon={mdiTag} onClick={handleNavigation} />
        {/snippet}
      </Timeline>
    {:else}
      <TreeItemThumbnails items={tag.children} icon={mdiTag} onClick={handleNavigation} />
    {/if}
  </section>
</UserPageLayout>

<section>
  {#if assetMultiSelectManager.selectionActive}
    <div class="fixed top-0 start-0 w-full">
      <AssetSelectControlBar>
        {@const Actions = getAssetBulkActions($t)}
        <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />
        <CreateSharedLink />
        <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
        <ActionButton action={Actions.AddToAlbum} />
        <FavoriteAction
          removeFavorite={assetMultiSelectManager.isAllFavorite}
          onFavorite={(ids, isFavorite) => timelineManager.update(ids, (asset) => (asset.isFavorite = isFavorite))}
        ></FavoriteAction>
        <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
      </AssetSelectControlBar>
    </div>
  {/if}
</section>

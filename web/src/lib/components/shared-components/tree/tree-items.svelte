<script lang="ts">
  import Tree from '$lib/components/shared-components/tree/tree.svelte';
  import { type TreeNode } from '$lib/utils/tree-utils';

  interface Props {
    tree: TreeNode;
    active: string;
    icons: { default: string; active: string };
    getLink: (path: string) => string;
    handleClick?: () => void;
  }

  let { tree, active, icons, getLink, handleClick }: Props = $props();
</script>

<ul class="list-none ms-2">
  {#each tree.children as node (node.color ? node.path + node.color : node.path)}
    <li>
      <Tree {node} {icons} {active} {getLink} {handleClick} />
    </li>
  {/each}
</ul>

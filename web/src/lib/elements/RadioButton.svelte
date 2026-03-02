<script lang="ts">
  interface Props {
    id: string;
    label: string;
    name: string;
    value: string;
    group?: string | undefined;
  }

  let { id, label, name, value, group = $bindable(undefined) }: Props = $props();
</script>

<div class="flex items-baseline">
  <input type="radio" {name} {id} {value} class="focus-visible:ring cursor-pointer" bind:group />
  <label class="cursor-pointer pl-2" for={id}>{label}</label>
</div>

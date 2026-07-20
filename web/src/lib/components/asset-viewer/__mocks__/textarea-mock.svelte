<script lang="ts">
  interface Props {
    value?: string;
    class?: string;
    rows?: number;
    grow?: boolean;
    shape?: string;
    placeholder?: string;
    onfocusout?: (event: FocusEvent) => void;
    [key: string]: unknown;
  }

  let {
    value = $bindable(''),
    class: className = '',
    rows = 1,
    placeholder = '',
    onfocusout,
  }: Props = $props();
</script>

<textarea
  data-testid="autogrow-textarea"
  class={className}
  {rows}
  {placeholder}
  bind:value
  {onfocusout}
></textarea>

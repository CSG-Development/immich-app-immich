<script lang="ts">
  import { goto } from '$app/navigation';
  import AuthPageLayout from '$lib/components/layouts/AuthPageLayout.svelte';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { serverConfigManager } from '$lib/managers/server-config-manager.svelte';
  import { Route } from '$lib/route';
  import { oauth } from '$lib/utils';
  import { getServerErrorMessage, handleError } from '$lib/utils/handle-error';
  import { login, type LoginResponseDto } from '@immich/sdk';
  import { Alert, Button, Field, Input, PasswordInput, Stack } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let errorMessage: string = $state('');
  let email = $state('');
  let password = $state('');
  let oauthError = $state('');
  let loading = $state(false);
  let oauthLoading = $state(true);

  const serverConfig = $derived(serverConfigManager.value);
  const canSubmit = $derived(email.trim().length > 0 && password.length > 0);

  const inputClass =
    'bg-neutral-50! border-neutral-300 focus-within:border-neutral-400 dark:bg-neutral-800! dark:border-neutral-600';

  const onSuccess = async (user: LoginResponseDto) => {
    await goto(data.continueUrl, { invalidateAll: true });
    eventManager.emit('AuthLogin', user);
  };

  const onFirstLogin = () => goto(Route.changePassword());
  const onOnboarding = () => goto(Route.onboarding());

  onMount(async () => {
    if (!featureFlagsManager.value.oauth) {
      oauthLoading = false;
      return;
    }

    if (oauth.isCallback(globalThis.location)) {
      try {
        const user = await oauth.login(globalThis.location);

        if (!user.isOnboarded) {
          await onOnboarding();
          return;
        }

        await onSuccess(user);
        return;
      } catch (error) {
        console.error('Error [login-form] [oauth.callback]', error);
        oauthError = getServerErrorMessage(error) || $t('errors.unable_to_complete_oauth_login');
        oauthLoading = false;
        return;
      }
    }

    try {
      if (
        (featureFlagsManager.value.oauthAutoLaunch && !oauth.isAutoLaunchDisabled(globalThis.location)) ||
        oauth.isAutoLaunchEnabled(globalThis.location)
      ) {
        await goto(Route.login({ autoLaunch: 0 }), { replaceState: true });
        await oauth.authorize(globalThis.location);
        return;
      }
    } catch (error) {
      handleError(error, $t('errors.unable_to_connect'));
    }

    oauthLoading = false;
  });

  const handleLogin = async () => {
    try {
      errorMessage = '';
      loading = true;
      const user = await login({ loginCredentialDto: { email, password } });

      if (user.isAdmin && !serverConfigManager.value.isOnboarded) {
        await serverConfigManager.loadServerConfig();
        if (!serverConfigManager.value.isOnboarded) {
          await onOnboarding();
          return;
        }
      }

      // change the user password before we onboard them
      if (!user.isAdmin && user.shouldChangePassword) {
        await onFirstLogin();
        return;
      }

      // We want to onboard after the first login since their password will change
      // and handleLogin will be called again (relogin). We then do onboarding on that next call.
      if (!user.isOnboarded) {
        await onOnboarding();
        return;
      }

      await onSuccess(user);
      return;
    } catch (error) {
      errorMessage = getServerErrorMessage(error) || $t('errors.incorrect_email_or_password');
      loading = false;
      return;
    }
  };

  const handleOAuthLogin = async () => {
    oauthLoading = true;
    oauthError = '';
    const success = await oauth.authorize(globalThis.location);
    if (!success) {
      oauthLoading = false;
      oauthError = $t('errors.unable_to_login_with_oauth');
    }
  };

  const onsubmit = async (event: Event) => {
    event.preventDefault();
    if (!canSubmit || loading) {
      return;
    }
    await handleLogin();
  };
</script>

<AuthPageLayout title={data.meta.title} isLogin>
  <Stack gap={6} class="h-full">
    {#if serverConfig.loginPageMessage}
      <Alert color="primary" class="mb-2">
        <!-- eslint-disable-next-line svelte/no-at-html-tags -->
        {@html serverConfig.loginPageMessage}
      </Alert>
    {/if}

    {#if !oauthLoading && featureFlagsManager.value.passwordLogin}
      <form {onsubmit} class="flex flex-1 flex-col gap-4">
        {#if errorMessage}
          <Alert color="danger" class="[&_p]:first-letter:uppercase" title={errorMessage} closable />
        {/if}

      <Field>
        <Input
          id="email"
          name="email"
          type="email"
          autocomplete="email"
          shape="round"
          size="giant"
          placeholder={$t('email')}
          aria-label={$t('email')}
          class={inputClass}
          bind:value={email}
        />
      </Field>
      <Field>
        <PasswordInput
          id="password"
          autocomplete="current-password"
          shape="round"
          size="giant"
          placeholder={$t('password')}
          aria-label={$t('password')}
          class={inputClass}
          bind:value={password}
        />
      </Field>
        <!-- <button
          type="button"
          class="w-fit text-base font-semibold text-emerald-700 hover:text-emerald-800 dark:text-emerald-500"
        >
          {$t('reset_password')}
        </button> -->

        <div class="mt-auto pt-16">
          <Button
            type="submit"
            size="giant"
            shape="round"
            color="success"
            fullWidth
            {loading}
            disabled={!canSubmit || loading}
            class="bg-[rgb(110,190,73)]! text-dark! not-disabled:hover:bg-[rgb(98,172,64)]! disabled:bg-[rgb(231,231,231)]! disabled:text-dark/40! disabled:opacity-100 dark:disabled:bg-[rgb(93,93,93)]! dark:disabled:text-white/40!"
          >
            {$t('to_login')}
          </Button>
        </div>
      </form>
    {/if}

    {#if featureFlagsManager.value.oauth}
      {#if featureFlagsManager.value.passwordLogin}
        <div class="inline-flex w-full items-center justify-center my-4">
          <hr class="my-4 h-px w-3/4 border-0 bg-gray-200 dark:bg-gray-600" />
          <span
            class="absolute start-1/2 -translate-x-1/2 bg-white px-3 font-medium text-gray-900 dark:bg-neutral-900 dark:text-white uppercase"
          >
            {$t('or')}
          </span>
        </div>
      {/if}
      {#if oauthError}
        <Alert color="danger" title={oauthError} closable />
      {/if}
      <Button
        shape="round"
        loading={loading || oauthLoading}
        disabled={loading || oauthLoading}
        size="large"
        fullWidth
        color={featureFlagsManager.value.passwordLogin ? 'secondary' : 'primary'}
        onclick={handleOAuthLogin}
      >
        {serverConfig.oauthButtonText}
      </Button>
    {/if}

    {#if !featureFlagsManager.value.passwordLogin && !featureFlagsManager.value.oauth}
      <Alert color="warning" title={$t('login_has_been_disabled')} />
    {/if}
  </Stack>
</AuthPageLayout>

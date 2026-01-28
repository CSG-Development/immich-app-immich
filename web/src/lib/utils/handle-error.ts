import { isHttpError } from '@immich/sdk';
import type { Component } from 'svelte';
import { notificationController, NotificationType } from '../components/shared-components/notification/notification';

export function getServerErrorMessage(error: unknown) {
  if (!isHttpError(error)) {
    return;
  }

  // errors for endpoints without return types aren't parsed as json
  let data = error.data;
  if (typeof data === 'string') {
    try {
      data = JSON.parse(data);
    } catch {
      // Not a JSON string
    }
  }

  return data?.message || error.message;
}

interface ApiError extends Error {
  status: number;
}

export function handleError(error: unknown, message: string, component?: Component) {
  if ((error as ApiError)?.name === 'AbortError') {
    return;
  }

  console.error(`[handleError]: ${message}`, error, (error as ApiError)?.stack);

  try {
    let serverMessage = getServerErrorMessage(error);
    if (serverMessage) {
      serverMessage = `${String(serverMessage).slice(0, 75)}\n${(error as ApiError)?.status >= 500 ? '(Personal Cloud Photos Server Error)' : ''}`;
    }

    const errorMessage = serverMessage || message;

    notificationController.show({
      message: errorMessage,
      type: NotificationType.Error,
      ...(!!component ? { component } : {}),
    });

    return errorMessage;
  } catch (error) {
    console.error(error);
    return message;
  }
}

import NotificationComponentTest from '$lib/components/shared-components/notification/__tests__/notification-component-test.svelte';
import '@testing-library/jest-dom';
import { cleanup } from '@testing-library/svelte';
import { renderWithTooltips } from '$tests/helpers';
import { NotificationType, type ComponentNotification, type Notification } from '../notification';
import NotificationCard from '../notification-card.svelte';

describe('NotificationCard component', () => {
  it('disposes timeout if already removed from the DOM', () => {
    vi.spyOn(globalThis, 'clearTimeout');

    const notification: Notification = {
      id: 1234,
      message: 'Notification message',
      timeout: 1000,
      type: NotificationType.Info,
      action: { type: 'discard' },
    };

    renderWithTooltips(NotificationCard, { notification });

    cleanup();
    expect(globalThis.clearTimeout).toHaveBeenCalledTimes(1);
  });

  it('shows message and title', () => {
    const notification: Notification = {
      id: 1234,
      message: 'Notification message',
      timeout: 1000,
      type: NotificationType.Info,
      action: { type: 'discard' },
    };

    const sut = renderWithTooltips(NotificationCard, { notification });

    expect(sut.getByTestId('title')).toHaveTextContent('info');
    expect(sut.getByTestId('message')).toHaveTextContent('Notification message');
  });

  it('makes all buttons non-focusable and hidden from screen readers', () => {
    const notification: Notification = {
      id: 1234,
      message: 'Notification message',
      timeout: 1000,
      type: NotificationType.Info,
      action: { type: 'discard' },
      button: {
        text: 'button',
        onClick: vi.fn(),
      },
    };

    const sut = renderWithTooltips(NotificationCard, { notification });
    const buttons = sut.container.querySelectorAll('button');

    expect(buttons).toHaveLength(2);
    for (let i = 0; i < buttons.length; i++) {
      expect(buttons[i].getAttribute('tabindex')).toBe('-1');
      expect(buttons[i].getAttribute('aria-hidden')).toBe('true');
    }
  });

  it('shows title and renders component', () => {
    const notification: ComponentNotification<{ href: string }> = {
      id: 1234,
      type: NotificationType.Info,
      timeout: 1,
      action: { type: 'discard' },
      component: {
        type: NotificationComponentTest,
        props: {
          href: 'link',
        },
      },
    };

    const sut = renderWithTooltips(NotificationCard, { notification });

    expect(sut.getByTestId('title')).toHaveTextContent('info');
    expect(sut.getByTestId('message').innerHTML.replaceAll('<!---->', '')).toEqual(
      'Notification <b>message</b> with <a href="link">link</a>',
    );
  });
});

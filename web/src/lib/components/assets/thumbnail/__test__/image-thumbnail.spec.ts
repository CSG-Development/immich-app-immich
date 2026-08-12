import ImageThumbnail from '$lib/components/assets/thumbnail/image-thumbnail.svelte';
import { fireEvent, render } from '@testing-library/svelte';

vi.mock('$lib/utils/sw-messaging', () => ({
  cancelImageUrl: vi.fn(),
}));

describe('ImageThumbnail component', () => {
  beforeAll(() => {
    Element.prototype.animate = vi.fn().mockImplementation(() => ({
      cancel: () => {},
    }));
  });

  it('keeps alt empty until the image has loaded', async () => {
    const { baseElement } = render(ImageThumbnail, {
      url: 'http://localhost/img.png',
      altText: 'test',
      widthStyle: '250px',
    });

    const img = baseElement.querySelector('img')!;
    expect(img.getAttribute('alt')).toBe('');

    await fireEvent.load(img);
    expect(img.getAttribute('alt')).toBe('test');
  });
});

import { cancelImageUrl } from '$lib/utils/sw-messaging';

export function loadImage(src: string, onLoad: () => void, onError: () => void, onStart?: () => void) {
  let destroyed = false;
  let loaded = false;

  const handleLoad = () => {
    if (destroyed) {
      return;
    }
    loaded = true;
    onLoad();
  };
  const handleError = () => !destroyed && onError();

  const img = document.createElement('img');
  img.addEventListener('load', handleLoad);
  img.addEventListener('error', handleError);

  onStart?.();
  img.src = src;

  return () => {
    destroyed = true;
    img.removeEventListener('load', handleLoad);
    img.removeEventListener('error', handleError);
    // Keep completed responses in the service worker pending map for remounts.
    if (!loaded) {
      cancelImageUrl(src);
    }
    img.remove();
  };
}

export type LoadImageFunction = typeof loadImage;

import { DEFAULT_ALBUM_NAME, resolveAlbumName } from '$lib/utils/album-name';

describe('resolveAlbumName', () => {
  it('returns the trimmed name when provided', () => {
    expect(resolveAlbumName('  Vacation  ')).toBe('Vacation');
  });

  it('defaults blank names to Untitled Album', () => {
    expect(resolveAlbumName()).toBe(DEFAULT_ALBUM_NAME);
    expect(resolveAlbumName('')).toBe(DEFAULT_ALBUM_NAME);
    expect(resolveAlbumName('   ')).toBe(DEFAULT_ALBUM_NAME);
    expect(resolveAlbumName(null)).toBe(DEFAULT_ALBUM_NAME);
  });
});

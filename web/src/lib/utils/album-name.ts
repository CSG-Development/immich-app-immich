/** Matches the database default on `album.albumName`. */
export const DEFAULT_ALBUM_NAME = 'Untitled Album';

export const resolveAlbumName = (name?: string | null) => {
  const trimmed = name?.trim();
  return trimmed || DEFAULT_ALBUM_NAME;
};

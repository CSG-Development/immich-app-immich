/**
 * Encode a string or Uint8Array into a URL-safe base64 string.
 * Example: "abc" → "YWJj"
 */
export function toBase64URL(input: string | Uint8Array): string {
  const buffer = typeof input === 'string' ? Buffer.from(input, 'utf8') : Buffer.from(input);
  return buffer
    .toString('base64')
    .replace(/\+/g, '-') // Replace '+' with '-'
    .replace(/\//g, '_') // Replace '/' with '_'
    .replace(/=+$/, ''); // Remove trailing '='
}

/**
 * Decode a URL-safe base64 string back into a Uint8Array.
 * Example: "YWJj" → Uint8Array([97, 98, 99])
 */
export function fromBase64URL(base64url: string): Uint8Array {
  const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
  const pad = base64.length % 4 ? 4 - (base64.length % 4) : 0;
  return new Uint8Array(Buffer.from(base64 + '='.repeat(pad), 'base64'));
}

import { enhancedImages } from '@sveltejs/enhanced-img';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { svelteTesting } from '@testing-library/svelte/vite';
import fs from 'node:fs';
import path from 'node:path';
import { visualizer } from 'rollup-plugin-visualizer';
import { defineConfig, type Plugin, type ProxyOptions, type UserConfig } from 'vite';

const upstream = {
  target: process.env.IMMICH_SERVER_URL || 'http://immich-server:2283/',
  secure: true,
  changeOrigin: true,
  logLevel: 'info',
  ws: true,
};

const proxy: Record<string, string | ProxyOptions> = {
  '/photos/api': upstream,
  '/.well-known/immich': upstream,
  '/custom.css': upstream,
};

const MIME_BY_EXT: Record<string, string> = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

/**
 * Vite's publicDir is named `static`, so requests to `/static/...` are treated as a
 * mistaken publicDir prefix and 404. This fork keeps assets under `static/static/`
 * (URLs `/photos/static/...`); serve that nested folder explicitly in dev.
 */
function serveNestedStatic(): Plugin {
  const nestedDir = path.resolve(__dirname, 'static/static');
  const urlPrefix = '/photos/static/';

  return {
    name: 'serve-nested-static',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const rawUrl = req.url?.split('?')[0] ?? '';
        if (!rawUrl.startsWith(urlPrefix)) {
          next();
          return;
        }

        const relativePath = decodeURIComponent(rawUrl.slice(urlPrefix.length));
        if (!relativePath || relativePath.includes('\0') || path.isAbsolute(relativePath)) {
          next();
          return;
        }

        const filePath = path.resolve(nestedDir, relativePath);
        if (!filePath.startsWith(nestedDir + path.sep) && filePath !== nestedDir) {
          next();
          return;
        }

        if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
          next();
          return;
        }

        res.statusCode = 200;
        res.setHeader('Content-Type', MIME_BY_EXT[path.extname(filePath).toLowerCase()] ?? 'application/octet-stream');
        fs.createReadStream(filePath).pipe(res);
      });
    },
  };
}

export default defineConfig({
  build: {
    target: 'es2022',
  },
  resolve: {
    alias: {
      'xmlhttprequest-ssl': './node_modules/engine.io-client/lib/xmlhttprequest.js',
      // eslint-disable-next-line unicorn/prefer-module
      '@test-data': path.resolve(__dirname, './src/test-data'),
      // '@immich/ui': path.resolve(__dirname, '../../ui'),
      tabbable: 'tabbable/src/index.js',
    },
  },
  server: {
    // connect to a remote backend during web-only development
    proxy,
    allowedHosts: true,
  },
  plugins: [
    /* viteStaticCopy({
      targets: [
        { src: 'flutter_app/build/web/**', dest: 'flutter' },
        {
          src: 'flutter_app/build/web/assets/**',
          dest: 'assets',
        },
      ],
    }), */
    serveNestedStatic(),
    enhancedImages(),
    tailwindcss(),
    sveltekit(),
    process.env.BUILD_STATS === 'true'
      ? visualizer({
          emitFile: true,
          filename: 'stats.html',
        })
      : undefined,
    svelteTesting(),
  ],
  optimizeDeps: {
    entries: ['src/**/*.{svelte,ts,html}'],
  },
  test: {
    name: 'web:unit',
    include: ['src/**/*.{test,spec}.{js,ts}'],
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./src/test-data/setup.ts'],
    sequence: {
      hooks: 'list',
    },
    env: {
      TZ: 'UTC',
    },
  },
} as UserConfig);

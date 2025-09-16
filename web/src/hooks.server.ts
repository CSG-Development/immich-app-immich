import roboto from '$lib/assets/fonts/roboto/Roboto.ttf?url';
import robotoMono from '$lib/assets/fonts/roboto/RobotoMono.ttf?url';
import type { Handle } from '@sveltejs/kit';

// only used during the build to replace the variables from app.html
export const handle = (async ({ event, resolve }) => {
  return resolve(event, {
    transformPageChunk: ({ html }) => {
      return html.replace('%app.font%', roboto).replace('%app.monofont%', robotoMono);
    },
  });
}) satisfies Handle;

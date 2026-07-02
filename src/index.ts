import { createApp, logStartup } from './app.js';
import { env } from './config/env.js';

const app = createApp();

app.listen(env.PORT, () => {
  logStartup(env.PORT);
  // eslint-disable-next-line no-console
  console.log(`Chess backend running at http://localhost:${env.PORT}`);
});

import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

// Operator-only command: exclusive writes prevent replacing existing deployment credentials.
const domain = process.env.API_DOMAIN;
if (!domain || !/^[a-z0-9.-]+$/.test(domain)) throw new Error('Set API_DOMAIN');
const input = JSON.parse(await readFile(process.argv[2], 'utf8'));
const password = randomBytes(24).toString('base64url');
input.password = password;
await writeFile('.env', `POSTGRES_PASSWORD=${randomBytes(32).toString('hex')}\nAPI_DOMAIN=${domain}\n`, { mode: 0o600, flag: 'wx' });
await writeFile('account.private.json', JSON.stringify(input, null, 2), { mode: 0o600, flag: 'wx' });
await writeFile('access.private.json', JSON.stringify({ server: `https://${domain}`, email: input.email, password }, null, 2), { mode: 0o600, flag: 'wx' });
console.log('Credentials saved locally; not printed.');

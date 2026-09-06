import { readFile, writeFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';

const domain = process.argv[2];
if (!domain || !/^[a-z0-9.-]+$/.test(domain)) throw new Error('Supply a DNS hostname');
const env = parseEnv(await readFile('.env', 'utf8'));
env.API_DOMAIN = domain;
await writeFile('.env', Object.entries(env).map(([key,value])=>`${key}=${JSON.stringify(value)}`).join('\n')+'\n', {mode:0o600});
const access = JSON.parse(await readFile('access.private.json','utf8'));
access.server = `https://${domain}`;
await writeFile('access.private.json', JSON.stringify(access,null,2), {mode:0o600});
console.log('Domain updated; credentials unchanged.');

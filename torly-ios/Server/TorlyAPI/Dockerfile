FROM node:22-bookworm-slim AS dependencies
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.17.1 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile

FROM node:22-bookworm-slim
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3100
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY --chown=node:node package.json *.js ./
COPY --chown=node:node schema ./schema
COPY --chown=node:node public ./public
USER node
EXPOSE 3100
CMD ["node", "server.js"]

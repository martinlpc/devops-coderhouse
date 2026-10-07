FROM node:24-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable
RUN pnpm install --frozen-lockfile --prod

FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node src ./src
USER node
EXPOSE 3000
CMD ["node", "src/server.js"]






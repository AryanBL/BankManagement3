# syntax=docker/dockerfile:1.7
FROM node:22-bookworm-slim

ENV NODE_ENV=production
WORKDIR /app

# Keep dependency installation cacheable and deterministic.
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force

COPY --chown=node:node src ./src

USER node
EXPOSE 4000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=12 \
  CMD node -e "fetch('http://127.0.0.1:4000/api/health').then(async r=>{if(!r.ok){console.error(await r.text());process.exit(1)}}).catch(e=>{console.error(e);process.exit(1)})"

CMD ["node", "src/server.js"]

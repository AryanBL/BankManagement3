# syntax=docker/dockerfile:1.7
FROM node:22-bookworm-slim

ENV NODE_ENV=production \
    FRONTEND_HOST=0.0.0.0 \
    FRONTEND_PORT=5500
WORKDIR /app

COPY --chown=node:node . .

USER node
EXPOSE 5500

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=12 \
  CMD node -e "fetch('http://127.0.0.1:5500/').then(async r=>{if(!r.ok){console.error(await r.text());process.exit(1)}}).catch(e=>{console.error(e);process.exit(1)})"

CMD ["node", "frontend-server.js"]

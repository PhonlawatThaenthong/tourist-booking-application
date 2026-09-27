# ---- build stage ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- production stage ----
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
# App code stays root-owned (read-only to the process); only uploads is writable.
RUN mkdir -p uploads/slips && chown -R node:node uploads
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]

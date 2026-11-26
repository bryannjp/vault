# check=skip=SecretsUsedInArgOrEnv
# (Docker flags VITE_TOKEN_ADDRESS as a possible secret because of the word "TOKEN". It's a public contract address.)

# Stage 1: build the static files with Node.
FROM node:22-alpine AS build
WORKDIR /app

# Dependencies first: this layer is cached and only re-runs when package*.json change.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# Vite reads VITE_* environment variables at build time and writes them into the JavaScript.
ARG VITE_RPC_URL
ARG VITE_CHAIN_ID
ARG VITE_TOKEN_ADDRESS
ARG VITE_VAULT_ADDRESS
RUN npm run build

# Stage 2: serve them with nginx. The final image has no Node, no source code, no node_modules.
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
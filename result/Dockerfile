# Pin specific alpine base image
FROM node:18.19.1-alpine

WORKDIR /usr/app

# Copy dependency definitions
COPY package*.json ./

RUN npm ci && npm cache clean --force

# Copy application files
COPY . .

# Run as non-root user (Alpine comes with built-in 'node' user)
RUN chown -R node:node /usr/app
USER node

EXPOSE 80

CMD ["node", "server.js"]

#!/usr/bin/env bash

set -e

PROJECT="mini-laravel-video-chat"

echo "🚀 Creating $PROJECT..."

mkdir -p "$PROJECT"/{services,frontend,infrastructure}
cd "$PROJECT"

# --------------------------------------------------
# Laravel services
# --------------------------------------------------

echo "📦 Creating Laravel services..."

composer create-project laravel/laravel services/auth
composer create-project laravel/laravel services/call

# --------------------------------------------------
# Signaling service
# --------------------------------------------------

echo "🔌 Creating WebSocket signaling service..."

mkdir -p services/signaling
cd services/signaling

cat > package.json <<'EOF'
{
  "name": "video-chat-signaling",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
EOF

cat > server.js <<'EOF'
const WebSocket = require("ws");

const PORT = process.env.PORT || 3000;

const wss = new WebSocket.Server({
    port: PORT
});

const rooms = new Map();

function broadcast(roomId, sender, message) {
    const clients = rooms.get(roomId) || new Set();

    for (const client of clients) {
        if (client !== sender && client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(message));
        }
    }
}

wss.on("connection", (socket) => {
    let roomId = null;

    socket.on("message", (raw) => {
        let message;

        try {
            message = JSON.parse(raw);
        } catch {
            return;
        }

        if (message.type === "join") {
            roomId = message.roomId;

            if (!rooms.has(roomId)) {
                rooms.set(roomId, new Set());
            }

            rooms.get(roomId).add(socket);

            broadcast(roomId, socket, {
                type: "user-joined"
            });

            return;
        }

        if (!roomId) {
            return;
        }

        broadcast(roomId, socket, message);
    });

    socket.on("close", () => {
        if (!roomId || !rooms.has(roomId)) {
            return;
        }

        rooms.get(roomId).delete(socket);

        broadcast(roomId, socket, {
            type: "user-left"
        });

        if (rooms.get(roomId).size === 0) {
            rooms.delete(roomId);
        }
    });
});

console.log(`Signaling server listening on :${PORT}`);
EOF

npm install

cd ../..

# --------------------------------------------------
# Docker Compose
# --------------------------------------------------

echo "🐳 Creating Docker Compose..."

cat > docker-compose.yml <<'EOF'
services:

  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: video_chat
      POSTGRES_USER: video
      POSTGRES_PASSWORD: video
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  signaling:
    build:
      context: ./services/signaling
    command: npm start
    environment:
      PORT: 3000
    ports:
      - "3000:3000"

volumes:
  postgres_data:
EOF

# --------------------------------------------------
# Signaling Dockerfile
# --------------------------------------------------

cat > services/signaling/Dockerfile <<'EOF'
FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --omit=dev

COPY server.js .

EXPOSE 3000

CMD ["npm", "start"]
EOF

# --------------------------------------------------
# Environment
# --------------------------------------------------

cat > .env.example <<'EOF'
APP_ENV=local

POSTGRES_DB=video_chat
POSTGRES_USER=video
POSTGRES_PASSWORD=video

REDIS_HOST=redis
REDIS_PORT=6379

SIGNALING_URL=ws://localhost:3000
EOF

# --------------------------------------------------
# Makefile
# --------------------------------------------------

cat > Makefile <<'EOF'
up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

signaling:
	cd services/signaling && npm start

auth:
	cd services/auth && php artisan serve --port=8001

call:
	cd services/call && php artisan serve --port=8002
EOF

echo ""
echo "✅ Project created!"
echo ""
echo "Next:"
echo ""
echo "  cd $PROJECT"
echo "  docker compose up -d"
echo ""
echo "Services:"
echo "  Auth API       : http://localhost:8001"
echo "  Call API       : http://localhost:8002"
echo "  Signaling WS   : ws://localhost:3000"
echo "  PostgreSQL     : localhost:5432"
echo "  Redis          : localhost:6379"

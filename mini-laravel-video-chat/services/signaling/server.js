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

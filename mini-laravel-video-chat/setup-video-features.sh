#!/usr/bin/env bash

set -e

echo "🚀 Ajout des fonctionnalités Video Chat..."

# ============================================================
# CONFIGURATION
# ============================================================

PROJECT_DIR="mini-laravel-video-chat"
FRONTEND_DIR="$PROJECT_DIR/frontend"
CALL_SERVICE="$PROJECT_DIR/services/call"

# ============================================================
# VERIFICATION
# ============================================================

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Projet introuvable : $PROJECT_DIR"
    echo ""
    echo "Lance ce script depuis le dossier parent."
    exit 1
fi

if [ ! -f "$FRONTEND_DIR/package.json" ]; then
    echo "❌ Frontend Vue introuvable."
    exit 1
fi

if [ ! -d "$CALL_SERVICE" ]; then
    echo "❌ Laravel Call Service introuvable : $CALL_SERVICE"
    exit 1
fi

echo "✅ Projet détecté"

# ============================================================
# 1. LARAVEL CALL SERVICE
# ============================================================

echo ""
echo "📦 Configuration du Call Service..."

cd "$CALL_SERVICE"

# ------------------------------------------------------------
# Model Room
# ------------------------------------------------------------

mkdir -p app/Models
mkdir -p app/Http/Controllers

cat > app/Models/Room.php <<'EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class Room extends Model
{
    protected $fillable = [
        'room_id',
        'name',
    ];

    protected static function booted()
    {
        static::creating(function ($room) {
            if (!$room->room_id) {
                $room->room_id = (string) Str::uuid();
            }
        });
    }
}
EOF

# ------------------------------------------------------------
# Migration
# ------------------------------------------------------------

mkdir -p database/migrations

TIMESTAMP=$(date +%Y_%m_%d_%H%M%S)

cat > "database/migrations/${TIMESTAMP}_create_rooms_table.php" <<'EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('rooms', function (Blueprint $table) {
            $table->id();

            $table->uuid('room_id')
                ->unique();

            $table->string('name')
                ->nullable();

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rooms');
    }
};
EOF

# ------------------------------------------------------------
# Controller
# ------------------------------------------------------------

cat > app/Http/Controllers/RoomController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Models\Room;
use Illuminate\Http\Request;

class RoomController extends Controller
{
    public function store(Request $request)
    {
        $room = Room::create([
            'name' => $request->input('name'),
        ]);

        return response()->json([
            'success' => true,
            'room' => [
                'id' => $room->room_id,
                'name' => $room->name,
            ],
        ], 201);
    }

    public function show(string $roomId)
    {
        $room = Room::where('room_id', $roomId)->first();

        if (!$room) {
            return response()->json([
                'success' => false,
                'message' => 'Room not found',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'room' => [
                'id' => $room->room_id,
                'name' => $room->name,
            ],
        ]);
    }

    public function destroy(string $roomId)
    {
        $room = Room::where('room_id', $roomId)->first();

        if (!$room) {
            return response()->json([
                'success' => false,
                'message' => 'Room not found',
            ], 404);
        }

        $room->delete();

        return response()->json([
            'success' => true,
        ]);
    }
}
EOF

# ------------------------------------------------------------
# API routes
# ------------------------------------------------------------

mkdir -p routes

if [ ! -f routes/api.php ]; then
    touch routes/api.php
fi

if ! grep -q "RoomController" routes/api.php; then

cat >> routes/api.php <<'EOF'

use App\Http\Controllers\RoomController;

Route::post('/rooms', [RoomController::class, 'store']);
Route::get('/rooms/{roomId}', [RoomController::class, 'show']);
Route::delete('/rooms/{roomId}', [RoomController::class, 'destroy']);
EOF

fi

# ------------------------------------------------------------
# Migration
# ------------------------------------------------------------

echo ""
echo "🗄️ Migration Laravel..."

php artisan migrate --force || {
    echo ""
    echo "⚠️ Migration impossible."
    echo "Vérifie la connexion PostgreSQL dans services/call/.env"
    echo ""
}

cd "../../.."

# ============================================================
# 2. FRONTEND
# ============================================================

echo ""
echo "🎨 Configuration du frontend..."

cd "$FRONTEND_DIR"

# ------------------------------------------------------------
# Vue Router
# ------------------------------------------------------------

npm install vue-router

# ------------------------------------------------------------
# main.js
# ------------------------------------------------------------

cat > src/main.js <<'EOF'
import { createApp } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'

import App from './App.vue'

const routes = [
    {
        path: '/',
        component: App
    },
    {
        path: '/room/:roomId',
        component: App
    }
]

const router = createRouter({
    history: createWebHistory(),
    routes
})

createApp(App)
    .use(router)
    .mount('#app')
EOF

# ------------------------------------------------------------
# App.vue
# ------------------------------------------------------------

cat > src/App.vue <<'EOF'
<script setup>

import {
    ref,
    computed,
    nextTick,
    onMounted,
    onBeforeUnmount
} from 'vue'

import {
    useRoute,
    useRouter
} from 'vue-router'

const route = useRoute()
const router = useRouter()

// ============================================================
// CONFIG
// ============================================================

const SIGNALING_URL =
    import.meta.env.VITE_SIGNALING_URL ||
    'ws://localhost:3000'

const CALL_API_URL =
    import.meta.env.VITE_CALL_API_URL ||
    'http://localhost:8002/api'

// ============================================================
// STATE
// ============================================================

const roomId = ref('')
const roomName = ref('')

const connected = ref(false)
const connecting = ref(false)

const status = ref('Prêt')

const microphoneEnabled = ref(true)
const cameraEnabled = ref(true)

const localVideo = ref(null)
const remoteVideo = ref(null)

const copied = ref(false)

let socket = null
let peer = null
let localStream = null

// ============================================================
// COMPUTED
// ============================================================

const roomUrl = computed(() => {

    if (!roomId.value) {
        return ''
    }

    return `${window.location.origin}/room/${roomId.value}`
})

// ============================================================
// CREATE ROOM
// ============================================================

async function createRoom() {

    try {

        status.value = 'Création de la room...'

        const response = await fetch(
            `${CALL_API_URL}/rooms`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    name: roomName.value || 'Video Call'
                })
            }
        )

        if (!response.ok) {
            throw new Error(
                `HTTP ${response.status}`
            )
        }

        const data = await response.json()

        roomId.value = data.room.id

        await router.push(
            `/room/${roomId.value}`
        )

        status.value =
            'Room créée'

    } catch (error) {

        console.error(
            'Room creation error:',
            error
        )

        status.value =
            'Impossible de créer la room'
    }
}

// ============================================================
// JOIN
// ============================================================

async function joinRoom() {

    if (!roomId.value) {

        status.value =
            'Room ID manquant'

        return
    }

    if (connected.value) {
        return
    }

    connecting.value = true

    try {

        status.value =
            'Demande caméra/micro...'

        localStream =
            await navigator.mediaDevices.getUserMedia({
                video: true,
                audio: true
            })

        status.value =
            'Connexion au signaling...'

        socket =
            new WebSocket(SIGNALING_URL)

        socket.onopen = async () => {

            console.log(
                '🔌 WebSocket connected'
            )

            connected.value = true
            connecting.value = false

            await nextTick()

            if (localVideo.value) {
                localVideo.value.srcObject =
                    localStream
            }

            status.value =
                'En attente du participant...'

            socket.send(
                JSON.stringify({
                    type: 'join',
                    roomId: roomId.value
                })
            )
        }

        socket.onmessage =
            async (event) => {

                const message =
                    JSON.parse(event.data)

                console.log(
                    '📨 SIGNAL:',
                    message
                )

                if (
                    message.type ===
                    'user-joined'
                ) {

                    status.value =
                        'Participant trouvé'

                    await createPeer(true)
                }

                if (
                    message.type ===
                    'offer'
                ) {

                    await createPeer(false)

                    await peer.setRemoteDescription(
                        new RTCSessionDescription(
                            message.offer
                        )
                    )

                    const answer =
                        await peer.createAnswer()

                    await peer.setLocalDescription(
                        answer
                    )

                    socket.send(
                        JSON.stringify({
                            type: 'answer',
                            answer
                        })
                    )
                }

                if (
                    message.type ===
                    'answer'
                ) {

                    if (!peer) {
                        return
                    }

                    await peer.setRemoteDescription(
                        new RTCSessionDescription(
                            message.answer
                        )
                    )
                }

                if (
                    message.type ===
                    'ice-candidate'
                ) {

                    if (
                        !peer ||
                        !message.candidate
                    ) {
                        return
                    }

                    try {

                        await peer.addIceCandidate(
                            new RTCIceCandidate(
                                message.candidate
                            )
                        )

                    } catch (error) {

                        console.error(
                            'ICE error:',
                            error
                        )
                    }
                }

                if (
                    message.type ===
                    'user-left'
                ) {

                    status.value =
                        'Le participant a quitté'

                    if (remoteVideo.value) {
                        remoteVideo.value.srcObject =
                            null
                    }

                    closePeer()
                }
            }

        socket.onerror = error => {

            console.error(
                'WebSocket error:',
                error
            )

            connecting.value = false
            status.value =
                'Erreur WebSocket'
        }

        socket.onclose = () => {

            console.log(
                'WebSocket closed'
            )

            connected.value = false
        }

    } catch (error) {

        console.error(
            'Camera/Micro error:',
            error
        )

        connecting.value = false

        status.value =
            `Erreur caméra/micro: ${error.name}`
    }
}

// ============================================================
// WEBRTC
// ============================================================

async function createPeer(initiator) {

    if (peer) {
        return
    }

    peer =
        new RTCPeerConnection({
            iceServers: [
                {
                    urls:
                        'stun:stun.l.google.com:19302'
                }
            ]
        })

    localStream
        .getTracks()
        .forEach(track => {

            peer.addTrack(
                track,
                localStream
            )
        })

    peer.ontrack = event => {

        console.log(
            '🎥 Remote stream'
        )

        if (remoteVideo.value) {

            remoteVideo.value.srcObject =
                event.streams[0]
        }

        status.value =
            '🟢 Appel connecté'
    }

    peer.onicecandidate = event => {

        if (
            event.candidate &&
            socket &&
            socket.readyState ===
                WebSocket.OPEN
        ) {

            socket.send(
                JSON.stringify({
                    type:
                        'ice-candidate',
                    candidate:
                        event.candidate
                })
            )
        }
    }

    peer.onconnectionstatechange =
        () => {

            if (!peer) {
                return
            }

            console.log(
                'WebRTC:',
                peer.connectionState
            )

            if (
                peer.connectionState ===
                'connected'
            ) {

                status.value =
                    '🟢 Appel connecté'
            }

            if (
                peer.connectionState ===
                    'disconnected' ||
                peer.connectionState ===
                    'failed'
            ) {

                status.value =
                    '🔴 Connexion interrompue'
            }
        }

    if (initiator) {

        const offer =
            await peer.createOffer()

        await peer.setLocalDescription(
            offer
        )

        socket.send(
            JSON.stringify({
                type: 'offer',
                offer
            })
        )
    }
}

// ============================================================
// MICROPHONE
// ============================================================

function toggleMicrophone() {

    if (!localStream) {
        return
    }

    microphoneEnabled.value =
        !microphoneEnabled.value

    localStream
        .getAudioTracks()
        .forEach(track => {

            track.enabled =
                microphoneEnabled.value
        })
}

// ============================================================
// CAMERA
// ============================================================

function toggleCamera() {

    if (!localStream) {
        return
    }

    cameraEnabled.value =
        !cameraEnabled.value

    localStream
        .getVideoTracks()
        .forEach(track => {

            track.enabled =
                cameraEnabled.value
        })
}

// ============================================================
// COPY ROOM LINK
// ============================================================

async function copyRoomLink() {

    if (!roomUrl.value) {
        return
    }

    try {

        await navigator.clipboard.writeText(
            roomUrl.value
        )

        copied.value = true

        setTimeout(() => {
            copied.value = false
        }, 2000)

    } catch (error) {

        console.error(error)
    }
}

// ============================================================
// LEAVE
// ============================================================

function closePeer() {

    if (peer) {

        peer.close()
        peer = null
    }
}

function leaveRoom() {

    closePeer()

    if (socket) {

        socket.close()
        socket = null
    }

    if (localStream) {

        localStream
            .getTracks()
            .forEach(track =>
                track.stop()
            )

        localStream = null
    }

    if (localVideo.value) {
        localVideo.value.srcObject =
            null
    }

    if (remoteVideo.value) {
        remoteVideo.value.srcObject =
            null
    }

    connected.value = false
    connecting.value = false

    status.value =
        'Appel terminé'
}

// ============================================================
// INITIAL ROOM
// ============================================================

onMounted(async () => {

    if (route.params.roomId) {

        roomId.value =
            route.params.roomId

        await nextTick()
    }
})

onBeforeUnmount(() => {

    leaveRoom()
})

</script>

<template>

    <main class="app">

        <!-- HOME -->

        <section
            v-if="!roomId && !connected"
            class="home"
        >

            <div class="card">

                <h1>
                    🎥 Mini Video Chat
                </h1>

                <p>
                    Crée une room et partage
                    le lien avec ton correspondant.
                </p>

                <input
                    v-model="roomName"
                    placeholder="Nom de la room"
                />

                <button
                    @click="createRoom"
                >
                    Créer une room
                </button>

            </div>

        </section>

        <!-- ROOM -->

        <section
            v-else
            class="room"
        >

            <header class="header">

                <div>

                    <h1>
                        🎥 Video Chat
                    </h1>

                    <small>
                        Room:
                        {{ roomId }}
                    </small>

                </div>

                <button
                    class="share"
                    @click="copyRoomLink"
                >
                    {{
                        copied
                            ? '✓ Copié'
                            : '🔗 Partager'
                    }}
                </button>

            </header>

            <p class="status">
                {{ status }}
            </p>

            <!-- BEFORE JOIN -->

            <section
                v-if="!connected"
                class="join"
            >

                <div class="room-info">

                    <h2>
                        Rejoindre la room
                    </h2>

                    <p>
                        Partage ce lien :
                    </p>

                    <input
                        readonly
                        :value="roomUrl"
                        @click="$event.target.select()"
                    />

                </div>

                <button
                    :disabled="connecting"
                    @click="joinRoom"
                >
                    {{
                        connecting
                            ? 'Connexion...'
                            : '🎥 Rejoindre'
                    }}
                </button>

            </section>

            <!-- CALL -->

            <section
                v-else
                class="call"
            >

                <div class="videos">

                    <div class="video-card">

                        <span class="label">
                            Moi
                        </span>

                        <video
                            ref="localVideo"
                            autoplay
                            muted
                            playsinline
                        />

                        <div
                            v-if="!cameraEnabled"
                            class="camera-off"
                        >
                            📷 Caméra désactivée
                        </div>

                    </div>

                    <div class="video-card">

                        <span class="label">
                            Participant
                        </span>

                        <video
                            ref="remoteVideo"
                            autoplay
                            playsinline
                        />

                    </div>

                </div>

                <!-- CONTROLS -->

                <div class="controls">

                    <button
                        :class="{
                            active:
                                microphoneEnabled
                        }"
                        @click="toggleMicrophone"
                    >
                        {{
                            microphoneEnabled
                                ? '🎤 Micro'
                                : '🔇 Micro'
                        }}
                    </button>

                    <button
                        :class="{
                            active:
                                cameraEnabled
                        }"
                        @click="toggleCamera"
                    >
                        {{
                            cameraEnabled
                                ? '📹 Caméra'
                                : '📷 Caméra'
                        }}
                    </button>

                    <button
                        class="hangup"
                        @click="leaveRoom"
                    >
                        📞 Raccrocher
                    </button>

                </div>

            </section>

        </section>

    </main>

</template>

<style>

* {
    box-sizing: border-box;
}

body {
    margin: 0;

    font-family:
        Inter,
        Arial,
        sans-serif;

    background:
        #0f172a;

    color: white;
}

button,
input {
    font: inherit;
}

button {
    border: 0;
    cursor: pointer;
}

button:disabled {
    opacity: .5;
    cursor: not-allowed;
}

/* HOME */

.app {
    min-height: 100vh;
}

.home {
    min-height: 100vh;

    display: flex;

    justify-content: center;
    align-items: center;

    padding: 20px;
}

.card {
    width: 100%;
    max-width: 450px;

    padding: 40px;

    background: #1e293b;

    border-radius: 20px;

    text-align: center;

    box-shadow:
        0 20px 50px
        rgba(0, 0, 0, .3);
}

.card h1 {
    margin-top: 0;
}

.card p {
    color: #94a3b8;

    line-height: 1.6;
}

.card input {
    width: 100%;

    margin:
        20px 0 10px;

    padding: 14px;

    border: 1px solid #475569;

    border-radius: 10px;

    background: #0f172a;

    color: white;
}

.card button {
    width: 100%;

    padding: 14px;

    border-radius: 10px;

    background: #2563eb;

    color: white;
}

/* ROOM */

.room {
    max-width: 1200px;

    margin: auto;

    padding: 25px;
}

.header {
    display: flex;

    align-items: center;

    justify-content:
        space-between;
}

.header h1 {
    margin-bottom: 5px;
}

.header small {
    color: #64748b;
}

.share {
    padding: 10px 15px;

    border-radius: 8px;

    background: #334155;

    color: white;
}

.status {
    text-align: center;

    padding: 15px;

    color: #93c5fd;
}

/* JOIN */

.join {
    max-width: 600px;

    margin:
        50px auto;

    text-align: center;
}

.room-info {
    padding: 30px;

    background: #1e293b;

    border-radius: 15px;

    margin-bottom: 20px;
}

.room-info input {
    width: 100%;

    padding: 12px;

    border: 0;

    border-radius: 8px;

    background: #0f172a;

    color: white;
}

.join > button {
    padding: 14px 30px;

    border-radius: 10px;

    background: #2563eb;

    color: white;
}

/* VIDEO */

.videos {
    display: grid;

    grid-template-columns:
        repeat(2, 1fr);

    gap: 20px;
}

.video-card {
    position: relative;

    overflow: hidden;

    background: black;

    border-radius: 15px;

    min-height: 500px;
}

.video-card video {
    width: 100%;
    height: 500px;

    object-fit: cover;

    display: block;
}

.label {
    position: absolute;

    top: 15px;
    left: 15px;

    z-index: 5;

    padding:
        7px 12px;

    background:
        rgba(0, 0, 0, .6);

    border-radius: 8px;
}

.camera-off {
    position: absolute;

    inset: 0;

    display: flex;

    align-items: center;

    justify-content: center;

    background: #020617;

    color: #94a3b8;

    font-size: 20px;
}

/* CONTROLS */

.controls {
    display: flex;

    justify-content: center;

    gap: 12px;

    margin-top: 25px;
}

.controls button {
    padding:
        13px 20px;

    border-radius: 10px;

    background: #334155;

    color: white;
}

.controls button.active {
    background: #2563eb;
}

.controls .hangup {
    background: #dc2626;
}

@media (max-width: 750px) {

    .videos {
        grid-template-columns: 1fr;
    }

    .video-card,
    .video-card video {
        min-height: 300px;
        height: 300px;
    }

    .header {
        gap: 15px;
    }

    .controls {
        flex-wrap: wrap;
    }

}

</style>
EOF

# ============================================================
# 3. FRONTEND ENV
# ============================================================

echo ""
echo "🔧 Configuration environnement..."

if [ ! -f .env ]; then
    cat > .env <<'EOF'
VITE_SIGNALING_URL=ws://localhost:3000
VITE_CALL_API_URL=http://localhost:8002/api
EOF
else

    if ! grep -q "^VITE_CALL_API_URL=" .env; then
        echo "VITE_CALL_API_URL=http://localhost:8002/api" >> .env
    fi

fi

# ============================================================
# FIN
# ============================================================

echo ""
echo "=============================================="
echo "✅ FONCTIONNALITÉS INSTALLÉES"
echo "=============================================="
echo ""
echo "Frontend :"
echo "  cd $FRONTEND_DIR"
echo "  npm run dev -- --host 0.0.0.0"
echo ""
echo "Call API :"
echo "  cd $CALL_SERVICE"
echo "  php artisan serve --host=0.0.0.0 --port=8002"
echo ""
echo "Signaling :"
echo "  docker compose up -d --build signaling"
echo ""
echo "=============================================="
echo "Fonctionnalités :"
echo "  ✅ Création de room"
echo "  ✅ URL partageable"
echo "  ✅ Rejoindre une room"
echo "  ✅ WebRTC"
echo "  ✅ Micro ON/OFF"
echo "  ✅ Caméra ON/OFF"
echo "  ✅ Raccrocher"
echo "  ✅ API Laravel Rooms"
echo "=============================================="
echo ""

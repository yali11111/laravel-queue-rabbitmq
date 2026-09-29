#!/usr/bin/env bash

set -e

echo "🚀 Installation du frontend Mini Laravel Video Chat..."

PROJECT_DIR="mini-laravel-video-chat"
FRONTEND_DIR="$PROJECT_DIR/frontend"

# --------------------------------------------------
# Vérification du projet
# --------------------------------------------------

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Le dossier $PROJECT_DIR n'existe pas."
    echo ""
    echo "Lance d'abord le script principal."
    exit 1
fi

# --------------------------------------------------
# Création du frontend Vue
# --------------------------------------------------

if [ ! -f "$FRONTEND_DIR/package.json" ]; then

    echo "📦 Le frontend Vue n'existe pas encore."
    echo "📦 Création de Vue + Vite..."

    rm -rf "$FRONTEND_DIR"

    npm create vite@latest "$FRONTEND_DIR" -- \
        --template vue

else

    echo "✅ Frontend Vue détecté."

fi

cd "$FRONTEND_DIR"

# --------------------------------------------------
# Installation npm
# --------------------------------------------------

echo "📦 Installation des dépendances..."

npm install

# --------------------------------------------------
# App.vue
# --------------------------------------------------

echo "📝 Configuration de App.vue..."

cat > src/App.vue <<'EOF'
<script setup>
import { ref, onBeforeUnmount } from 'vue'

const roomId = ref('')
const connected = ref(false)
const status = ref('Déconnecté')

const localVideo = ref(null)
const remoteVideo = ref(null)

let socket = null
let peer = null
let localStream = null

const SIGNALING_URL =
  import.meta.env.VITE_SIGNALING_URL || 'ws://localhost:3000'

const rtcConfig = {
  iceServers: [
    {
      urls: 'stun:stun.l.google.com:19302'
    }
  ]
}

async function joinRoom() {

  if (!roomId.value.trim()) {
    alert('Veuillez entrer un Room ID')
    return
  }

  try {

    status.value = 'Accès à la caméra...'

    localStream = await navigator.mediaDevices.getUserMedia({
      video: true,
      audio: true
    })

    localVideo.value.srcObject = localStream

    status.value = 'Connexion au serveur...'

    socket = new WebSocket(SIGNALING_URL)

    socket.onopen = () => {

      connected.value = true
      status.value = 'En attente d'un participant...'

      socket.send(JSON.stringify({
        type: 'join',
        roomId: roomId.value
      }))
    }

    socket.onmessage = async (event) => {

      const message = JSON.parse(event.data)

      console.log('📨 Signal:', message)

      switch (message.type) {

        case 'user-joined':
          await createPeer(true)
          break

        case 'offer':
          await createPeer(false)

          await peer.setRemoteDescription(
            new RTCSessionDescription(message.offer)
          )

          const answer = await peer.createAnswer()

          await peer.setLocalDescription(answer)

          socket.send(JSON.stringify({
            type: 'answer',
            answer
          }))

          break

        case 'answer':

          if (!peer) {
            return
          }

          await peer.setRemoteDescription(
            new RTCSessionDescription(message.answer)
          )

          break

        case 'ice-candidate':

          if (!peer || !message.candidate) {
            return
          }

          try {

            await peer.addIceCandidate(
              new RTCIceCandidate(message.candidate)
            )

          } catch (error) {

            console.error(
              'Erreur ICE:',
              error
            )

          }

          break

        case 'user-left':

          status.value = 'Le participant a quitté'

          if (remoteVideo.value) {
            remoteVideo.value.srcObject = null
          }

          closePeer()

          break
      }
    }

    socket.onerror = (error) => {

      console.error(error)

      status.value = 'Erreur WebSocket'
    }

    socket.onclose = () => {

      connected.value = false

      if (status.value !== 'Déconnecté') {
        status.value = 'Connexion fermée'
      }
    }

  } catch (error) {

    console.error(error)

    status.value =
      'Impossible d’accéder à la caméra ou au microphone'
  }
}

async function createPeer(initiator) {

  if (peer) {
    return
  }

  console.log(
    'Création PeerConnection:',
    initiator
  )

  peer = new RTCPeerConnection(rtcConfig)

  localStream.getTracks().forEach(track => {
    peer.addTrack(track, localStream)
  })

  peer.ontrack = event => {

    console.log('🎥 Remote stream reçu')

    if (remoteVideo.value) {
      remoteVideo.value.srcObject =
        event.streams[0]
    }

    status.value = 'Appel en cours'
  }

  peer.onicecandidate = event => {

    if (
      event.candidate &&
      socket &&
      socket.readyState === WebSocket.OPEN
    ) {

      socket.send(JSON.stringify({
        type: 'ice-candidate',
        candidate: event.candidate
      }))
    }
  }

  peer.onconnectionstatechange = () => {

    if (!peer) {
      return
    }

    console.log(
      'WebRTC:',
      peer.connectionState
    )

    if (
      peer.connectionState === 'connected'
    ) {

      status.value = '🟢 Appel connecté'

    }

    if (
      peer.connectionState === 'disconnected' ||
      peer.connectionState === 'failed'
    ) {

      status.value =
        '🔴 Connexion WebRTC interrompue'
    }
  }

  if (initiator) {

    const offer =
      await peer.createOffer()

    await peer.setLocalDescription(
      offer
    )

    socket.send(JSON.stringify({
      type: 'offer',
      offer
    }))
  }
}

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
      .forEach(track => track.stop())

    localStream = null
  }

  if (localVideo.value) {
    localVideo.value.srcObject = null
  }

  if (remoteVideo.value) {
    remoteVideo.value.srcObject = null
  }

  connected.value = false
  status.value = 'Déconnecté'
}

onBeforeUnmount(() => {
  leaveRoom()
})
</script>

<template>

  <main class="container">

    <h1>🎥 Mini Video Chat</h1>

    <p class="status">
      {{ status }}
    </p>

    <!-- JOIN -->

    <section
      v-if="!connected"
      class="join"
    >

      <input
        v-model="roomId"
        placeholder="Room ID"
        @keyup.enter="joinRoom"
      />

      <button @click="joinRoom">
        Rejoindre
      </button>

    </section>

    <!-- CALL -->

    <section
      v-else
      class="call"
    >

      <div class="videos">

        <div class="video-box">

          <span>Moi</span>

          <video
            ref="localVideo"
            autoplay
            muted
            playsinline
          />

        </div>

        <div class="video-box">

          <span>Participant</span>

          <video
            ref="remoteVideo"
            autoplay
            playsinline
          />

        </div>

      </div>

      <div class="controls">

        <button
          class="danger"
          @click="leaveRoom"
        >
          Quitter
        </button>

      </div>

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
    Arial,
    Helvetica,
    sans-serif;

  background: #111827;
  color: white;
}

.container {
  max-width: 1100px;
  margin: auto;
  padding: 40px 20px;
}

h1 {
  text-align: center;
  margin-bottom: 20px;
}

.status {
  text-align: center;
  color: #93c5fd;
  margin-bottom: 30px;
}

.join {
  display: flex;
  justify-content: center;
  gap: 10px;
}

input {
  width: 280px;
  padding: 13px;

  border: none;
  border-radius: 8px;

  font-size: 16px;
}

button {
  padding: 13px 22px;

  border: none;
  border-radius: 8px;

  background: #2563eb;
  color: white;

  cursor: pointer;

  font-size: 15px;
}

button:hover {
  background: #1d4ed8;
}

.videos {
  display: grid;

  grid-template-columns:
    repeat(2, 1fr);

  gap: 20px;
}

.video-box {
  position: relative;

  background: black;

  border-radius: 12px;

  overflow: hidden;

  min-height: 400px;
}

.video-box span {
  position: absolute;

  top: 10px;
  left: 10px;

  z-index: 2;

  background:
    rgba(0, 0, 0, .6);

  padding: 6px 10px;

  border-radius: 6px;
}

video {
  width: 100%;
  height: 100%;

  min-height: 400px;

  object-fit: cover;

  display: block;
}

.controls {
  text-align: center;

  margin-top: 25px;
}

.danger {
  background: #dc2626;
}

.danger:hover {
  background: #b91c1c;
}

@media (max-width: 700px) {

  .videos {
    grid-template-columns: 1fr;
  }

  .video-box,
  video {
    min-height: 300px;
  }

  .join {
    flex-direction: column;
  }

  input {
    width: 100%;
  }

}

</style>
EOF

# --------------------------------------------------
# .env
# --------------------------------------------------

cat > .env <<'EOF'
VITE_SIGNALING_URL=ws://localhost:3000
EOF

# --------------------------------------------------
# Dockerfile
# --------------------------------------------------

cat > Dockerfile <<'EOF'
FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

EXPOSE 5173

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
EOF

echo ""
echo "=========================================="
echo "✅ FRONTEND INSTALLÉ"
echo "=========================================="
echo ""
echo "Pour démarrer :"
echo ""
echo "  cd $FRONTEND_DIR"
echo "  npm run dev"
echo ""
echo "Puis ouvrir :"
echo ""
echo "  http://localhost:5173"
echo ""
<script setup>
import { ref, onBeforeUnmount, nextTick } from 'vue'

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
console.log(' SIGNALING URL:', SIGNALING_URL)

const rtcConfig = {
  iceServers: [
    {
      urls: 'stun:stun.l.google.com:19302'
    }
  ]
}

async function joinRoom() {
  if (!roomId.value.trim()) {
    alert('Entre un Room ID')
    return
  }

  try {
    status.value = 'Demande caméra/micro...'

    localStream = await navigator.mediaDevices.getUserMedia({
      video: true,
      audio: true
    })

    await nextTick()

if (localVideo.value) {
  localVideo.value.srcObject = localStream
}

    status.value = 'Connexion au signaling...'

    socket = new WebSocket(SIGNALING_URL)

    socket.onopen = async () => {

  connected.value = true

  await nextTick()

  if (localVideo.value) {
    localVideo.value.srcObject = localStream
  }

  status.value = 'En attente du participant...'

  socket.send(JSON.stringify({
    type: 'join',
    roomId: roomId.value
  }))
}

    socket.onmessage = async (event) => {
      const message = JSON.parse(event.data)

      console.log('SIGNAL:', message)

      if (message.type === 'user-joined') {
        await createPeer(true)
      }

      if (message.type === 'offer') {
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
      }

      if (message.type === 'answer') {
        if (!peer) return

        await peer.setRemoteDescription(
          new RTCSessionDescription(message.answer)
        )
      }

      if (message.type === 'ice-candidate') {
        if (!peer || !message.candidate) return

        try {
          await peer.addIceCandidate(
            new RTCIceCandidate(message.candidate)
          )
        } catch (error) {
          console.error('ICE error:', error)
        }
      }

      if (message.type === 'user-left') {
        status.value = 'Participant parti'

        if (remoteVideo.value) {
          remoteVideo.value.srcObject = null
        }

        closePeer()
      }
    }

    socket.onerror = (error) => {
      console.error('WebSocket error:', error)
      status.value = 'Erreur WebSocket'
    }

    socket.onclose = () => {
      console.log('WebSocket fermé')
      connected.value = false
    }

  } catch (error) {
  console.error('CAMERA ERROR:', error)

  status.value =
    `Erreur caméra/micro: ${error.name} - ${error.message}`
}
}

async function createPeer(initiator) {
  if (peer) return

  peer = new RTCPeerConnection(rtcConfig)

  localStream.getTracks().forEach(track => {
    peer.addTrack(track, localStream)
  })

  peer.ontrack = event => {
    console.log('Remote video reçue')

    if (remoteVideo.value) {
      remoteVideo.value.srcObject = event.streams[0]
    }

    status.value = '🟢 Appel connecté'
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
    console.log(
      'WebRTC:',
      peer.connectionState
    )
  }

  if (initiator) {
    const offer = await peer.createOffer()

    await peer.setLocalDescription(offer)

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
    localStream.getTracks().forEach(track => track.stop())
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

    <h1>🎥 Mini Laravel Video Chat</h1>

    <p class="status">
      {{ status }}
    </p>

    <section v-if="!connected" class="join">

      <input
        v-model="roomId"
        placeholder="Room ID"
        @keyup.enter="joinRoom"
      />

      <button @click="joinRoom">
        Rejoindre
      </button>

    </section>

    <section v-else class="call">

      <div class="videos">

        <div class="video-box">
          <span>Moi</span>

          <video
            ref="localVideo"
            autoplay
            muted
            playsinline
          ></video>
        </div>

        <div class="video-box">
          <span>Participant</span>

          <video
            ref="remoteVideo"
            autoplay
            playsinline
          ></video>
        </div>

      </div>

      <div class="controls">

        <button
          class="danger"
          @click="leaveRoom"
        >
          Raccrocher
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
  background: #111827;
  color: white;
  font-family: Arial, sans-serif;
}

.container {
  max-width: 1100px;
  margin: auto;
  padding: 40px 20px;
}

h1 {
  text-align: center;
}

.status {
  text-align: center;
  color: #93c5fd;
  margin: 25px;
}

.join {
  display: flex;
  justify-content: center;
  gap: 10px;
}

input {
  padding: 14px;
  width: 280px;
  border: 0;
  border-radius: 8px;
  font-size: 16px;
}

button {
  padding: 14px 22px;
  border: 0;
  border-radius: 8px;
  background: #2563eb;
  color: white;
  cursor: pointer;
}

button:hover {
  background: #1d4ed8;
}

.videos {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}

.video-box {
  position: relative;
  background: black;
  border-radius: 12px;
  overflow: hidden;
}

.video-box span {
  position: absolute;
  top: 10px;
  left: 10px;
  z-index: 2;
  background: rgba(0, 0, 0, .6);
  padding: 6px 10px;
  border-radius: 6px;
}

video {
  display: block;
  width: 100%;
  height: 450px;
  object-fit: cover;
}

.controls {
  text-align: center;
  margin-top: 25px;
}

.danger {
  background: #dc2626;
}

@media (max-width: 700px) {
  .videos {
    grid-template-columns: 1fr;
  }
}
</style>

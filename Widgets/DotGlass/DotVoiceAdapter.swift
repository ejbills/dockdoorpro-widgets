import Foundation

/// Observe standard WebRTC inbound audio levels. Never capture microphone data,
/// record audio, replace playback, or synthesize another voice.
enum DotVoiceAdapter {
    static let source = #"""
    (() => {
      if (location.origin !== 'https://chatgpt.com' || window.__dotGlassVoice || !window.RTCPeerConnection) return;
      const NativePeer = window.RTCPeerConnection, peers = new Set();
      let busy = false, previous = '', stopped = false;
      class MeteredPeer extends NativePeer {
        constructor(...args) {
          super(...args); peers.add(this);
          this.addEventListener('connectionstatechange', () => {
            if (this.connectionState === 'closed' || this.connectionState === 'failed') peers.delete(this);
            sample();
          });
          this.addEventListener('track', () => sample());
        }
      }
      window.RTCPeerConnection = MeteredPeer;
      const energyHistory = new Map();
      async function sample() {
        if (busy || stopped) return;
        busy = true;
        let connected = false, level = 0, meterAvailable = false, muted = true;
        try {
          for (const peer of peers) {
            if (peer.connectionState !== 'connected') continue;
            const senders = peer.getSenders().filter(s => s.track?.kind === 'audio' && s.track.readyState === 'live');
            if (!senders.length) continue;
            const receivers = peer.getReceivers().filter(r => r.track?.kind === 'audio' && r.track.readyState === 'live');
            if (!receivers.length) continue;
            connected = true;
            if (senders.some(s => s.track.enabled)) muted = false;
            const stats = await peer.getStats();
            stats.forEach(stat => {
              if (stat.type !== 'inbound-rtp' || (stat.kind || stat.mediaType) !== 'audio') return;
              if (Number.isFinite(stat.audioLevel)) {
                meterAvailable = true; level = Math.max(level, stat.audioLevel);
              } else if (Number.isFinite(stat.totalAudioEnergy) && Number.isFinite(stat.totalSamplesDuration)) {
                const old = energyHistory.get(stat.id);
                if (old && stat.totalSamplesDuration > old.duration) {
                  meterAvailable = true;
                  level = Math.max(level, Math.sqrt(Math.max(0, stat.totalAudioEnergy - old.energy) / (stat.totalSamplesDuration - old.duration)));
                }
                energyHistory.set(stat.id, {energy:stat.totalAudioEnergy, duration:stat.totalSamplesDuration});
              }
            });
          }
          const value = {connected, muted: connected && muted, level: Math.round(Math.min(1, level * 5) * 100) / 100, meterAvailable};
          const encoded = JSON.stringify(value);
          if (encoded !== previous) {previous = encoded; window.webkit?.messageHandlers.dotGlass.postMessage(value);}
        } catch (_) { /* Audio/session data is never logged. */ }
        finally {busy = false;}
      }
      window.__dotGlassVoice = {sample};
      window.addEventListener('pagehide', () => {stopped = true; peers.clear(); energyHistory.clear();});
    })();
    """#
}

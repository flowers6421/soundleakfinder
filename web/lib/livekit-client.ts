import { connect, Room, RoomEvent, Participant, ParticipantEvent, LocalAudioTrack } from 'livekit-client';

export class LiveKitClient {
  private room: Room | null = null;
  private serverUrl: string;
  private token: string;
  private roomName: string;
  private mediaStream: MediaStream;

  constructor(serverUrl: string, token: string, roomName: string, mediaStream: MediaStream) {
    this.serverUrl = serverUrl;
    this.token = token;
    this.roomName = roomName;
    this.mediaStream = mediaStream;
  }

  async connect(): Promise<void> {
    try {
      console.log('🔗 Connecting to LiveKit...');
      
      this.room = await connect(this.serverUrl, this.token, {
        audio: true,
        video: false,
        autoSubscribe: true,
      });

      // Publish local audio
      const audioTrack = this.mediaStream.getAudioTracks()[0];
      if (audioTrack) {
        await this.room.localParticipant.publishTrack(
          new LocalAudioTrack(audioTrack, {
            simulcast: false,
          })
        );
      }

      // Setup event listeners
      this.setupEventListeners();

      console.log('✅ Connected to LiveKit');
    } catch (error) {
      console.error('❌ Failed to connect to LiveKit:', error);
      throw error;
    }
  }

  private setupEventListeners(): void {
    if (!this.room) return;

    this.room.on(RoomEvent.ParticipantConnected, (participant: Participant) => {
      console.log(`👤 Participant connected: ${participant.name}`);
      this.setupParticipantListeners(participant);
    });

    this.room.on(RoomEvent.ParticipantDisconnected, (participant: Participant) => {
      console.log(`👤 Participant disconnected: ${participant.name}`);
    });

    this.room.on(RoomEvent.Disconnected, () => {
      console.log('🔌 Disconnected from LiveKit');
    });
  }

  private setupParticipantListeners(participant: Participant): void {
    participant.on(ParticipantEvent.TrackSubscribed, (track) => {
      console.log(`🎵 Track subscribed from ${participant.name}`);
    });

    participant.on(ParticipantEvent.TrackUnsubscribed, (track) => {
      console.log(`🎵 Track unsubscribed from ${participant.name}`);
    });
  }

  async disconnect(): Promise<void> {
    if (this.room) {
      await this.room.disconnect();
      this.room = null;
    }
  }

  getRoom(): Room | null {
    return this.room;
  }

  getParticipants(): Participant[] {
    return this.room?.participants.values() ? Array.from(this.room.participants.values()) : [];
  }
}


export class AudioProcessor {
  private audioContext: AudioContext;
  private mediaStream: MediaStream;
  private analyser: AnalyserNode;
  private source: MediaStreamAudioSourceNode;
  private animationId: number | null = null;
  private onLevelChange: (level: number) => void;
  private dataArray: Uint8Array;

  constructor(
    audioContext: AudioContext,
    mediaStream: MediaStream,
    onLevelChange: (level: number) => void
  ) {
    this.audioContext = audioContext;
    this.mediaStream = mediaStream;
    this.onLevelChange = onLevelChange;

    // Create analyser node
    this.analyser = audioContext.createAnalyser();
    this.analyser.fftSize = 2048;

    // Create source from media stream
    this.source = audioContext.createMediaStreamSource(mediaStream);
    this.source.connect(this.analyser);

    // Initialize data array
    this.dataArray = new Uint8Array(this.analyser.frequencyBinCount);
  }

  start(): void {
    this.updateLevel();
  }

  stop(): void {
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
  }

  private updateLevel(): void {
    this.analyser.getByteFrequencyData(this.dataArray);

    // Calculate RMS level
    let sum = 0;
    for (let i = 0; i < this.dataArray.length; i++) {
      sum += this.dataArray[i] * this.dataArray[i];
    }
    const rms = Math.sqrt(sum / this.dataArray.length) / 255;

    this.onLevelChange(rms);

    this.animationId = requestAnimationFrame(() => this.updateLevel());
  }

  getFrequencyData(): Uint8Array {
    this.analyser.getByteFrequencyData(this.dataArray);
    return this.dataArray;
  }

  getWaveformData(): Uint8Array {
    const waveData = new Uint8Array(this.analyser.fftSize);
    this.analyser.getByteTimeDomainData(waveData);
    return waveData;
  }
}


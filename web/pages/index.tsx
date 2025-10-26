import React, { useState, useEffect, useRef } from 'react';
import { LiveKitClient } from '../lib/livekit-client';
import { AudioProcessor } from '../lib/audio-processor';

export default function Home() {
  const [isConnected, setIsConnected] = useState(false);
  const [serverUrl, setServerUrl] = useState('');
  const [token, setToken] = useState('');
  const [roomName, setRoomName] = useState('');
  const [audioLevel, setAudioLevel] = useState(0);
  const [error, setError] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  
  const liveKitClientRef = useRef<LiveKitClient | null>(null);
  const audioProcessorRef = useRef<AudioProcessor | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  // Initialize audio context
  useEffect(() => {
    if (typeof window !== 'undefined') {
      audioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)();
    }
  }, []);

  // Request microphone permission and start recording
  const startRecording = async () => {
    try {
      setError('');
      
      // Request microphone access
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
          sampleRate: 48000,
        },
      });
      
      streamRef.current = stream;
      
      // Initialize audio processor
      if (audioContextRef.current) {
        audioProcessorRef.current = new AudioProcessor(
          audioContextRef.current,
          stream,
          (level) => setAudioLevel(level)
        );
        audioProcessorRef.current.start();
      }
      
      setIsRecording(true);
    } catch (err) {
      setError(`Microphone access denied: ${err}`);
    }
  };

  // Stop recording
  const stopRecording = () => {
    if (audioProcessorRef.current) {
      audioProcessorRef.current.stop();
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(track => track.stop());
    }
    setIsRecording(false);
    setAudioLevel(0);
  };

  // Connect to LiveKit
  const handleConnect = async () => {
    try {
      setError('');
      
      if (!serverUrl || !token || !roomName) {
        setError('Please fill in all connection details');
        return;
      }

      if (!isRecording) {
        await startRecording();
      }

      liveKitClientRef.current = new LiveKitClient(
        serverUrl,
        token,
        roomName,
        streamRef.current!
      );

      await liveKitClientRef.current.connect();
      setIsConnected(true);
    } catch (err) {
      setError(`Connection failed: ${err}`);
    }
  };

  // Disconnect from LiveKit
  const handleDisconnect = async () => {
    if (liveKitClientRef.current) {
      await liveKitClientRef.current.disconnect();
    }
    stopRecording();
    setIsConnected(false);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-8">
      <div className="max-w-md mx-auto bg-white rounded-lg shadow-lg p-6">
        <h1 className="text-3xl font-bold text-center mb-2 text-indigo-600">
          🔊 Sound Leak Finder
        </h1>
        <p className="text-center text-gray-600 mb-6">Remote Microphone Interface</p>

        {/* Status Indicator */}
        <div className="mb-6 p-4 bg-gray-50 rounded-lg">
          <div className="flex items-center gap-2 mb-2">
            <div
              className={`w-3 h-3 rounded-full ${
                isConnected ? 'bg-green-500' : 'bg-gray-400'
              }`}
            />
            <span className="text-sm font-medium">
              {isConnected ? 'Connected' : 'Disconnected'}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <div
              className={`w-3 h-3 rounded-full ${
                isRecording ? 'bg-red-500' : 'bg-gray-400'
              }`}
            />
            <span className="text-sm font-medium">
              {isRecording ? 'Recording' : 'Idle'}
            </span>
          </div>
        </div>

        {/* Audio Level Meter */}
        {isRecording && (
          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Audio Level
            </label>
            <div className="w-full bg-gray-200 rounded-full h-2">
              <div
                className="bg-indigo-600 h-2 rounded-full transition-all"
                style={{ width: `${Math.min(audioLevel * 100, 100)}%` }}
              />
            </div>
            <p className="text-xs text-gray-500 mt-1">
              {(audioLevel * 100).toFixed(1)}%
            </p>
          </div>
        )}

        {/* Connection Form */}
        {!isConnected ? (
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Server URL
              </label>
              <input
                type="text"
                placeholder="wss://livekit.example.com"
                value={serverUrl}
                onChange={(e) => setServerUrl(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Access Token
              </label>
              <input
                type="password"
                placeholder="Your access token"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Room Name
              </label>
              <input
                type="text"
                placeholder="room-name"
                value={roomName}
                onChange={(e) => setRoomName(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-md text-red-700 text-sm">
                {error}
              </div>
            )}

            <button
              onClick={handleConnect}
              className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-medium py-2 px-4 rounded-md transition-colors"
            >
              Connect
            </button>
          </div>
        ) : (
          <button
            onClick={handleDisconnect}
            className="w-full bg-red-600 hover:bg-red-700 text-white font-medium py-2 px-4 rounded-md transition-colors"
          >
            Disconnect
          </button>
        )}
      </div>
    </div>
  );
}


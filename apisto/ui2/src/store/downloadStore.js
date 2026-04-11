import { createSignal } from 'solid-js';
import { showToast } from '../components/Toast.jsx';

// In Cordova (file:// protocol) or production build, use absolute server URL
const isCordova = location.protocol === 'file:';
const isProd = import.meta.env.PROD;
const SERVER_URL = 'https://apisto-music.onrender.com';
const BASE = (isCordova || isProd) ? SERVER_URL : '';
const WS_BASE = (isCordova || isProd) ? 'wss://apisto-music.onrender.com' : `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}`;

function createDownloadStore() {
  const [searchResults, setSearchResults] = createSignal([]);
  const [isSearching, setIsSearching] = createSignal(false);
  const [isDownloading, setIsDownloading] = createSignal(false);
  const [isPaused, setIsPaused] = createSignal(false);
  const [downloadProgress, setDownloadProgress] = createSignal(0);
  const [downloadStatus, setDownloadStatus] = createSignal('Ready');
  const [downloadSpeed, setDownloadSpeed] = createSignal('');
  const [downloadSize, setDownloadSize] = createSignal('');
  const [errorMessage, setErrorMessage] = createSignal('');
  const [library, setLibrary] = createSignal([]);
  const [activeDownloadId, setActiveDownloadId] = createSignal(null);
  const [currentDownloadMeta, setCurrentDownloadMeta] = createSignal(null);
  // stored for resume
  let lastDownloadArgs = null;
  let ws = null;

  const search = async (query) => {
    if (!query.trim()) return;
    setIsSearching(true);
    setSearchResults([]);
    try {
      const response = await fetch(`${BASE}/api/search?q=${encodeURIComponent(query)}`);
      const data = await response.json();
      setSearchResults(data.results || []);
    } catch {
      setErrorMessage('Search failed');
    } finally {
      setIsSearching(false);
    }
  };

  const clearSearch = () => setSearchResults([]);

  const cancel = () => {
    if (ws) { ws.close(); ws = null; }
    setIsDownloading(false);
    setIsPaused(false);
    setDownloadProgress(0);
    setDownloadStatus('Ready');
    setDownloadSpeed('');
    setDownloadSize('');
    setCurrentDownloadMeta(null);
    lastDownloadArgs = null;
    showToast('Download cancelled', 'error');
  };

  const pause = () => {
    if (!isDownloading() || isPaused()) return;
    if (ws) { ws.close(); ws = null; }
    setIsPaused(true);
    setIsDownloading(false);
    setDownloadStatus('Paused');
    showToast('Download paused', 'info');
  };

  const resume = () => {
    if (!isPaused() || !lastDownloadArgs) return;
    setIsPaused(false);
    setDownloadProgress(0);
    showToast('Resuming download...', 'info');
    const [url, isVideo, quality, videoQuality, meta] = lastDownloadArgs;
    _startDownload(url, isVideo, quality, videoQuality, meta);
  };

  const _startDownload = (url, isVideo, quality, videoQuality, meta) => {
    const downloadId = Date.now().toString();
    setActiveDownloadId(downloadId);
    setIsDownloading(true);
    setDownloadStatus('Connecting...');
    setErrorMessage('');
    if (meta) setCurrentDownloadMeta(meta);

    ws = new WebSocket(`${WS_BASE}/api/download/${downloadId}`);
    ws.onopen = () => ws.send(JSON.stringify({ url, is_video: isVideo, quality, video_quality: videoQuality }));
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      setDownloadProgress(data.progress);
      setDownloadStatus(data.status);
      if (data.speed) setDownloadSpeed(data.speed);
      if (data.size) setDownloadSize(data.size);
      if (data.status === 'completed') {
        setIsDownloading(false);
        setIsPaused(false);
        setDownloadStatus('✓ Done!');
        showToast(`✓ Download complete: ${meta?.title || 'file'}`, 'success');
        loadLibrary();
        setTimeout(() => {
          if (!isDownloading()) {
            setDownloadProgress(0); setDownloadStatus('Ready');
            setDownloadSpeed(''); setDownloadSize('');
            setCurrentDownloadMeta(null); lastDownloadArgs = null;
          }
        }, 3000);
      } else if (data.status === 'failed') {
        setIsDownloading(false);
        setErrorMessage(data.error || 'Download failed');
        setDownloadStatus('Failed');
        showToast('Download failed', 'error');
      }
    };
    ws.onerror = () => { setIsDownloading(false); setErrorMessage('Connection error'); setDownloadStatus('Failed'); };
    ws.onclose = () => { if (isDownloading()) setIsDownloading(false); };
  };

  const downloadSong = (url, isVideo = false, quality = 320, videoQuality = 720, meta = null) => {
    if (isDownloading()) { showToast('Download already in progress', 'error'); return; }
    lastDownloadArgs = [url, isVideo, quality, videoQuality, meta];
    setDownloadProgress(0);
    _startDownload(url, isVideo, quality, videoQuality, meta);
  };

  const loadLibrary = async () => {
    try {
      const response = await fetch(`${BASE}/api/library`);
      const data = await response.json();
      setLibrary(data.files || []);
    } catch {}
  };

  const deleteSong = async (filePath) => {
    try {
      const res = await fetch(`${BASE}/api/library/${encodeURIComponent(filePath)}`, { method: 'DELETE' });
      const data = await res.json();
      if (data.success) { await loadLibrary(); showToast('File deleted', 'info'); }
    } catch {}
  };

  const clearError = () => setErrorMessage('');

  return {
    searchResults, isSearching, isDownloading, isPaused,
    downloadProgress, downloadStatus, downloadSpeed, downloadSize,
    errorMessage, library, activeDownloadId, currentDownloadMeta,
    search, clearSearch, downloadSong, pause, resume, cancel,
    loadLibrary, deleteSong, clearError,
  };
}

export const downloadStore = createDownloadStore();

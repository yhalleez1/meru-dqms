const express = require('express');
const cors = require('cors');
const path = require('path');
const http = require('http');
const WebSocket = require('ws');
const queueRoutes = require('./routes/queueRoutes');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws' });

// Store active clients
const clients = new Map();

// WebSocket connection handler
wss.on('connection', (ws) => {
    const clientId = Date.now().toString();
    clients.set(clientId, ws);
    console.log(`✅ WebSocket client connected: ${clientId} (${clients.size} total)`);
    
    ws.on('close', () => {
        clients.delete(clientId);
        console.log(`❌ WebSocket client disconnected: ${clientId} (${clients.size} remaining)`);
    });
    
    ws.on('error', (error) => {
        console.error(`⚠️ WebSocket error: ${error.message}`);
    });
});

// Function to broadcast message to all connected clients
function broadcastToAll(message) {
    clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(message));
        }
    });
}

// Function to broadcast to specific office
function broadcastToOffice(officeId, message) {
    clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify({ ...message, officeId }));
        }
    });
}

// Export for use in routes
app.wss = wss;
app.broadcastToAll = broadcastToAll;
app.broadcastToOffice = broadcastToOffice;

app.use(cors());                     // allow requests from different origins
app.use(express.json());              // parse JSON bodies
app.use('/api', queueRoutes);         // mount all routes under /api

// Serve static files from frontend directories
app.use('/simulator', express.static(path.join(__dirname, '../simulator')));
app.use('/staff', express.static(path.join(__dirname, '../staff')));
app.use('/display', express.static(path.join(__dirname, '../display')));
app.use('/student', express.static(path.join(__dirname, '../student')));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'Server is running' });
});

module.exports = { server, app, wss: app.wss, broadcastToAll: app.broadcastToAll, broadcastToOffice: app.broadcastToOffice };
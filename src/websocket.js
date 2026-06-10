// Echo — WebSocket Session Manager
// Handles HTTP upgrade handshakes and real-time push notifications
// from the server to the waiting laptop browser session.

const { WebSocketServer } = require('ws');
const { db } = require('./db');

const wss = new WebSocketServer({ noServer: true });

// Map of sessionId -> active WebSocket connection
const laptopSockets = new Map();

/**
 * Attach the WebSocket upgrade listener to the given HTTP server.
 * Validates that the session ID in the query string exists before
 * accepting the connection. Invalid requests are rejected immediately.
 *
 * @param {http.Server} server - The Node.js HTTP server instance.
 */
function attachWebSocket(server) {
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://localhost');

    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }

    const sessionId = url.searchParams.get('session');
    const sessionExists = sessionId &&
      db.prepare('SELECT id FROM login_sessions WHERE id = ?').get(sessionId);

    if (!sessionExists) {
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      laptopSockets.set(sessionId, ws);
      ws.on('close', () => {
        if (laptopSockets.get(sessionId) === ws) {
          laptopSockets.delete(sessionId);
        }
      });
    });
  });
}

/**
 * Send a JSON payload to the laptop browser that is waiting on the
 * given login session. Silently does nothing if the socket is absent
 * or no longer open.
 *
 * @param {string} sessionId - The login session identifier.
 * @param {object} payload   - The JSON-serialisable message to send.
 */
function notifyLaptop(sessionId, payload) {
  const ws = laptopSockets.get(sessionId);
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify(payload));
  }
}

module.exports = { attachWebSocket, notifyLaptop };

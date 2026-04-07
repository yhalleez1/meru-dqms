# Quick Reference: Frontend API Integration

## 🚀 For Frontend Developers

### Base URL
```
http://localhost:3000/api
```

---

## 📱 Simulator Integration

### Initialization
```javascript
const API = 'http://localhost:3000/api';

// Load offices on page load
async function loadOffices() {
    const response = await fetch(`${API}/offices`);
    const offices = await response.json();
    // Populate dropdown with offices
}
```

### Display Current Ticket (every 2 seconds)
```javascript
async function updateDisplay(officeId) {
    const response = await fetch(`${API}/current?officeId=${officeId}`);
    const data = await response.json();
    display.textContent = data.currentServing || 'NONE';
}
```

### Issue New Ticket
```javascript
async function issueTicket(officeId) {
    const response = await fetch(`${API}/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            officeId,
            issuedAt: new Date().toISOString()
        })
    });
    const data = await response.json();
    alert(`Ticket #${data.ticketNumber}`);
}
```

---

## 👔 Staff Dashboard Integration

### Session Management
```javascript
// After login
sessionStorage.setItem('staffId', data.id);
sessionStorage.setItem('staffName', data.name);
sessionStorage.setItem('officeId', data.officeId);
sessionStorage.setItem('officeName', data.officeName);

// When needed
const officeId = sessionStorage.getItem('officeId');
```

### Get Queue Status (auto-refresh every 2s)
```javascript
async function refreshQueue() {
    const officeId = sessionStorage.getItem('officeId');
    
    const [current, waiting] = await Promise.all([
        fetch(`${API}/current?officeId=${officeId}`),
        fetch(`${API}/waiting?officeId=${officeId}`)
    ]);
    
    const currData = await current.json();
    const waitData = await waiting.json();
    
    document.getElementById('current').textContent = 
        currData.currentServing || 'NONE';
    document.getElementById('waiting').textContent = 
        waitData.data.length || 0;
}

setInterval(refreshQueue, 2000);
```

### Call Next Ticket
```javascript
async function callNext() {
    const officeId = sessionStorage.getItem('officeId');
    
    const response = await fetch(`${API}/next`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ officeId })
    });
    
    if (!response.ok) {
        alert('No waiting tickets');
        return;
    }
    
    const data = await response.json();
    // Start 10-second countdown...
    // After countdown, start service timer
}
```

### Track Service Time
```javascript
let serviceStart = new Date();

// When service ends
async function finishService(ticketNumber) {
    const officeId = sessionStorage.getItem('officeId');
    const elapsedSeconds = Math.floor(
        (new Date() - serviceStart) / 1000
    );
    
    const response = await fetch(`${API}/elapsed`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            ticketNumber,
            elapsedSeconds,
            officeId
        })
    });
    
    // Continue with next ticket...
}
```

### Skip Current Ticket
```javascript
async function skipTicket(ticketNumber) {
    const officeId = sessionStorage.getItem('officeId');
    
    const response = await fetch(`${API}/skip/${ticketNumber}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ officeId })
    });
    
    if (response.ok) {
        // Refresh queue and continue
        await refreshQueue();
    }
}
```

### Display Daily Total
```javascript
async function loadDailyTotal() {
    const officeId = sessionStorage.getItem('officeId');
    
    const response = await fetch(
        `${API}/elapsed/total?officeId=${officeId}`
    );
    const data = await response.json();
    
    const minutes = Math.floor(data.totalSeconds / 60);
    const seconds = data.totalSeconds % 60;
    
    document.getElementById('totalTime').textContent = 
        `${String(minutes).padStart(2,'0')}:${String(seconds).padStart(2,'0')}`;
}

// Call on boot
loadDailyTotal();
```

---

## 🔐 Authentication Flow

### Login Page
```javascript
async function login(username, password) {
    const response = await fetch('http://localhost:3000/api/staff/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
    });
    
    if (!response.ok) {
        alert('Invalid credentials');
        return;
    }
    
    const data = await response.json();
    
    // Store in session
    sessionStorage.setItem('staffId', data.id);
    sessionStorage.setItem('staffName', data.name);
    sessionStorage.setItem('officeId', data.officeId);
    sessionStorage.setItem('officeName', data.officeName);
    
    // Redirect to dashboard
    window.location.href = '/staff/index.html';
}
```

### Logout
```javascript
function logout() {
    sessionStorage.clear();
    window.location.href = '/staff/login.html';
}
```

---

## ⚠️ Error Handling

### Standardize Error Handling
```javascript
async function apiCall(url, options = {}) {
    try {
        const response = await fetch(url, {
            headers: { 'Content-Type': 'application/json' },
            ...options
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Request failed');
        }
        
        return await response.json();
    } catch (err) {
        console.error('API Error:', err);
        showToast(err.message, 'error');
        return null;
    }
}

// Usage
const data = await apiCall(`${API}/offices`);
if (data) {
    // Process data
}
```

---

## 🔄 Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Process response data |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Check parameters |
| 401 | Unauthorized | Redirect to login |
| 403 | Forbidden | Check permissions |
| 404 | Not Found | Retry or show error |
| 500 | Server Error | Retry after delay |

---

## 📋 Response Examples

### List Endpoint
```json
{
  "success": true,
  "count": 5,
  "data": [
    { "id": "123", "name": "Office 1" },
    { "id": "456", "name": "Office 2" }
  ]
}
```

### Single Item Endpoint
```json
{
  "success": true,
  "data": {
    "ticket_number": 123,
    "status": "waiting"
  }
}
```

### Action Endpoint
```json
{
  "success": true,
  "message": "Ticket called",
  "ticketNumber": 124
}
```

### Error Response
```json
{
  "error": "Invalid office ID",
  "details": "officeId must be a UUID"
}
```

---

## 🎯 Common Patterns

### Pattern: Display Query Param
```javascript
// Get query parameter
function getQueryParam(name) {
    const params = new URLSearchParams(window.location.search);
    return params.get(name);
}

const officeId = getQueryParam('office') || sessionStorage.getItem('officeId');
```

### Pattern: Format Ticket Number
```javascript
function formatTicket(num) {
    return String(num).padStart(3, '0');  // 2 → "002"
}
```

### Pattern: Format Time
```javascript
function formatTime(seconds) {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${String(mins).padStart(2,'0')}:${String(secs).padStart(2,'0')}`;
}
```

### Pattern: Toast Notification
```javascript
function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        bottom: 30px;
        left: 50%;
        transform: translateX(-50%);
        background: ${type === 'error' ? '#e74c3c' : '#28a745'};
        color: white;
        padding: 12px 20px;
        border-radius: 20px;
        z-index: 9999;
    `;
    document.body.appendChild(toast);
    
    setTimeout(() => toast.remove(), 3000);
}
```

---

## 🧪 Testing Locally

### cURL Examples

**Get Offices**
```bash
curl http://localhost:3000/api/offices | jq
```

**Issue Ticket**
```bash
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{"officeId": "811d76ff-...", "issuedAt": "2026-03-31T..."}' | jq
```

**Login**
```bash
curl -X POST http://localhost:3000/api/staff/login \
  -H "Content-Type: application/json" \
  -d '{"username": "john", "password": "pass123"}' | jq
```

**Get Queue**
```bash
curl "http://localhost:3000/api/waiting?officeId=811d76ff-..." | jq
```

---

## 🪲 Debugging Tips

1. **Check Network Tab**
   - Open DevTools → Network
   - Verify correct URLs
   - Check request/response payloads

2. **Console Logging**
   ```javascript
   console.log('Request:', { officeId, ticketNumber });
   console.log('Response:', data);
   ```

3. **Mock Server Response**
   ```javascript
   // For testing without server
   async function mockApiCall(url) {
       if (url.includes('/offices')) {
           return { success: true, data: [{id: "1", name: "Main"}] };
       }
       return { success: true, data: {} };
   }
   ```

4. **Check Session Storage**
   ```javascript
   console.log(sessionStorage); // View all stored data
   ```

---

## 📚 Full Documentation

For complete endpoint reference, see **API_ENDPOINTS.md**

For implementation details, see **HARMONIZATION_SUMMARY.md**

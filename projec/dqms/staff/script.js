const API_BASE = 'http://localhost:3000/api';

// Get staff session data
const staffId   = sessionStorage.getItem('staffId');
const staffName = sessionStorage.getItem('staffName');
const officeId  = sessionStorage.getItem('officeId');
const officeName = sessionStorage.getItem('officeName') || 'the counter';

function formatTicketNumber(num) {
    return String(num).padStart(3, '0');
}

// 🔊 Text-to-speech announcement
function announceTicket(ticketNumber) {
    if (!window.speechSynthesis) return;
    window.speechSynthesis.cancel(); // stop any ongoing speech
    const text = `Attention please. Number ${formatTicketNumber(ticketNumber)}, kindly proceed to ${officeName}`;
    const speech = new SpeechSynthesisUtterance(text);
    speech.rate   = 0.8;
    speech.pitch  = 1;
    speech.volume = 1;
    window.speechSynthesis.speak(speech);
}

// Logout function
function doLogout() {
    sessionStorage.clear();
    window.location.href = '/staff/login.html';
}

document.addEventListener('DOMContentLoaded', async () => {
    // Ensure staff is authenticated and has officeId
    if (!staffId || !officeId) {
        alert('Invalid session. Please log in again.');
        window.location.href = '/staff/login.html';
        return;
    }

    const currentServingSpan = document.getElementById('currentServing');
    const callNextBtn        = document.getElementById('callNextBtn');
    const waitingList        = document.getElementById('waitingList');
    const totalWaitingSpan   = document.getElementById('totalWaiting');

    const missingElements = [];
    if (!currentServingSpan) missingElements.push('currentServing');
    if (!callNextBtn)        missingElements.push('callNextBtn');
    if (!waitingList)        missingElements.push('waitingList');
    if (!totalWaitingSpan)   missingElements.push('totalWaiting');
    if (missingElements.length > 0) {
        console.error('Missing DOM elements:', missingElements.join(', '));
        showToast('UI Error: Missing elements. Check console.', 'error');
        return;
    }


    // ── Toast notification ────────────────────────────────────────────────────
    function showToast(message, type = 'success') {
        const existing = document.getElementById('queueToast');
        if (existing) existing.remove();

        const toast = document.createElement('div');
        toast.id = 'queueToast';
        toast.innerText = message;
        toast.style.cssText = `
            position: fixed;
            bottom: 30px;
            left: 50%;
            transform: translateX(-50%);
            background: ${type === 'error' ? '#e74c3c' : type === 'info' ? '#667eea' : '#28a745'};
            color: white;
            padding: 14px 28px;
            border-radius: 25px;
            font-size: 1em;
            font-weight: bold;
            box-shadow: 0 4px 20px rgba(0,0,0,0.25);
            z-index: 9999;
            opacity: 0;
            transition: opacity 0.3s ease;
            white-space: nowrap;
        `;
        document.body.appendChild(toast);

        // Fade in
        requestAnimationFrame(() => {
            requestAnimationFrame(() => { toast.style.opacity = '1'; });
        });

        // Fade out and remove after 3s
        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }

    // ── State ─────────────────────────────────────────────────────────────────
    let currentServingNumber  = null;
    let serviceStartTime      = null;   // Date: set after countdown ends (student being served)
    let countdownInterval     = null;   // 10s post-call countdown
    let masterTickInterval    = null;   // drives live Elapsed + Total Time every second
    let completedSecondsTotal = 0;      // loaded from DB on boot + accumulated in session

    // ── Load today's total from database on boot ──────────────────────────────
    try {
        const res = await fetch(`${API_BASE}/elapsed/total?officeId=${officeId}`);
        if (res.ok) {
            const data = await res.json();
            completedSecondsTotal = data.totalSeconds || 0;
            console.log(`Loaded today's total elapsed from DB: ${completedSecondsTotal}s`);
        }
    } catch (err) {
        console.error('Could not load total elapsed from DB:', err);
    }

    // ── Formatters ────────────────────────────────────────────────────────────
    function formatHHMM(date) {
        return `${String(date.getHours()).padStart(2,'0')}:${String(date.getMinutes()).padStart(2,'0')}`;
    }

    function formatMMSS(s) {
        s = Math.max(0, Math.floor(s));
        return `${String(Math.floor(s / 60)).padStart(2,'0')}:${String(s % 60).padStart(2,'0')}`;
    }

    function liveElapsed() {
        if (!serviceStartTime) return 0;
        return Math.floor((Date.now() - serviceStartTime.getTime()) / 1000);
    }

    // ── Update Total Time button display ──────────────────────────────────────
    function updateTotalTimeDisplay() {
        const grandTotal = completedSecondsTotal + liveElapsed();
        document.getElementById('totalTimeBtn').innerText = `Total Time: ${formatMMSS(grandTotal)}`;
    }

    // Initialise Total Time display immediately with DB value
    updateTotalTimeDisplay();

    // ── Master tick — live Elapsed + Total Time every second ──────────────────
    function startMasterTick() {
        if (masterTickInterval) clearInterval(masterTickInterval);
        masterTickInterval = setInterval(() => {
            const elapsed = liveElapsed();
            document.getElementById('timeElapsed').innerText = formatMMSS(elapsed);
            updateTotalTimeDisplay();
        }, 1000);
    }

    function stopMasterTick() {
        if (masterTickInterval) { clearInterval(masterTickInterval); masterTickInterval = null; }
    }

    // ── Save elapsed to database ──────────────────────────────────────────────
    async function saveElapsedToDB(ticketNumber, elapsedSeconds) {
        try {
            const res = await fetch(`${API_BASE}/elapsed`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ticketNumber, elapsedSeconds, officeId })
            });
            if (!res.ok) {
                const err = await res.json().catch(() => ({}));
                console.error('saveElapsed failed:', res.status, err);
            } else {
                console.log(`Saved elapsed ${elapsedSeconds}s for ticket #${ticketNumber} to DB`);
            }
        } catch (err) {
            console.error('Failed to save elapsed to DB:', err);
        }
    }

    // ── Finalise previous ticket when "Call Next" is clicked ──────────────────
    // Stamps End Time, banks elapsed into completedSecondsTotal, saves to DB
    async function finalisePreviousTicket(previousTicketNumber) {
        if (!serviceStartTime) return;

        const endTime         = new Date();
        const durationSeconds = liveElapsed();

        // Stamp End Time, freeze Elapsed on display
        document.getElementById('endTime').innerText     = formatHHMM(endTime);
        document.getElementById('timeElapsed').innerText = formatMMSS(durationSeconds);
        document.getElementById('timeElapsed').classList.remove('blinking');

        // Bank into in-memory total
        completedSecondsTotal += durationSeconds;
        updateTotalTimeDisplay();

        // Persist to Firestore
        await saveElapsedToDB(previousTicketNumber, durationSeconds);

        serviceStartTime = null;
        stopMasterTick();
    }

    // ── Start tracking new student after countdown ────────────────────────────
    function startServiceTracking() {
        serviceStartTime = new Date();

        document.getElementById('startTime').innerText   = formatHHMM(serviceStartTime);
        document.getElementById('endTime').innerText     = '---';
        document.getElementById('timeElapsed').innerText = '00:00';
        document.getElementById('timeElapsed').classList.add('blinking');

        startMasterTick();
    }

    // ── Refresh queue data ────────────────────────────────────────────────────
    async function refresh() {
        try {
            const [currentRes, waitingRes] = await Promise.all([
                fetch(`${API_BASE}/current?officeId=${officeId}`),
                fetch(`${API_BASE}/waiting?officeId=${officeId}`)
            ]);
            if (!currentRes.ok) throw new Error(`HTTP ${currentRes.status}`);
            if (!waitingRes.ok) throw new Error(`HTTP ${waitingRes.status}`);

            const currentData = await currentRes.json();
            const waiting     = await waitingRes.json();

            if (waiting.length === 0) {
                currentServingNumber = null;
                currentServingSpan.innerText = 'NONE';
                // Queue empty: disable Call Next and stop any live elapsed ticking
                if (!countdownInterval) {
                    callNextBtn.disabled      = true;
                    callNextBtn.style.opacity = '0.4';
                    stopMasterTick();
                    serviceStartTime = null;
                }
            } else if (currentData.currentServing) {
                currentServingNumber = currentData.currentServing;
                currentServingSpan.innerText = formatTicketNumber(currentData.currentServing);
                if (!countdownInterval) {
                    callNextBtn.disabled      = false;
                    callNextBtn.style.opacity = '1';
                }
            } else {
                currentServingNumber = null;
                currentServingSpan.innerText = 'NONE';
                if (!countdownInterval) {
                    callNextBtn.disabled      = false;
                    callNextBtn.style.opacity = '1';
                }
            }

            totalWaitingSpan.innerText = waiting.length;
            waitingList.innerHTML = '';

            if (waiting.length === 0) {
                const li = document.createElement('li');
                li.innerText = 'No waiting tickets';
                li.style.cssText = 'text-align:center;color:#999;';
                waitingList.appendChild(li);
            } else {
                waiting.forEach((ticket, index) => {
                    const li = document.createElement('li');
                    li.innerHTML = `<strong>#${formatTicketNumber(ticket.ticketNumber)}</strong> <span style="color:#999;font-size:0.9em;">Position: ${index + 1}</span>`;
                    waitingList.appendChild(li);
                });
            }
        } catch (error) {
            console.error('Error refreshing data:', error);
            currentServingSpan.innerText = 'ERR';
            currentServingNumber = null;
            waitingList.innerHTML = '<li style="color:#dc3545;">Error loading waiting list</li>';
        }
    }

    // ── Call Next ─────────────────────────────────────────────────────────────
    callNextBtn.addEventListener('click', async () => {
        if (callNextBtn.disabled) return;

        // Capture the ticket number being finalised before refresh changes it
        const finalisingTicketNumber = currentServingNumber;

        // Finalise previous ticket: stamp End Time, bank + save elapsed to DB
        await finalisePreviousTicket(finalisingTicketNumber);

        callNextBtn.disabled      = true;
        callNextBtn.style.opacity = '0.6';
        callNextBtn.innerText     = 'Calling...';

        if (countdownInterval) { clearInterval(countdownInterval); countdownInterval = null; }

        const skipBtn = document.getElementById('skipBtn');
        skipBtn.style.display = 'none';
        skipBtn.disabled      = true;

        try {
            const response = await fetch(`${API_BASE}/next`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ officeId })
            });

            if (!response.ok) {
                if (response.status === 404) showToast('No waiting tickets', 'info');
                else throw new Error(`HTTP ${response.status}`);
                callNextBtn.innerText     = 'Call Next';
                callNextBtn.disabled      = false;
                callNextBtn.style.opacity = '1';
                return;
            }

            const data = await response.json();
            console.log(`Called ticket #${data.ticketNumber}`);
            
            // 🔊 Announce the ticket number via TTS
            announceTicket(data.ticketNumber);

            // Immediately update the current serving display
            currentServingNumber = data.ticketNumber;
            currentServingSpan.innerText = formatTicketNumber(data.ticketNumber);
            
            await refresh();

            // 10-second countdown — previous ticket info stays frozen on display
            let countdown = 10;
            callNextBtn.innerText = `✓ Called! (${countdown}s)`;

            // Show Skip button immediately during countdown
            skipBtn.innerText     = 'Skip Ticket';
            skipBtn.style.display = 'block';
            skipBtn.disabled      = false;
            skipBtn.style.opacity = '1';

            countdownInterval = setInterval(() => {
                countdown--;
                if (countdown > 0) {
                    callNextBtn.innerText = `✓ Called! (${countdown}s)`;
                } else {
                    clearInterval(countdownInterval);
                    countdownInterval = null;

                    // Reset display and start tracking new student
                    document.getElementById('startTime').innerText   = '---';
                    document.getElementById('endTime').innerText     = '---';
                    document.getElementById('timeElapsed').innerText = '00:00';
                    document.getElementById('timeElapsed').classList.remove('blinking');

                    startServiceTracking();

                    // Re-enable Call Next, Skip button already visible
                    callNextBtn.innerText     = 'Call Next';
                    callNextBtn.disabled      = false;
                    callNextBtn.style.opacity = '1';
                }
            }, 1000);

        } catch (error) {
            console.error('Error calling next ticket:', error);
            showToast('Failed to call next ticket', 'error');
            callNextBtn.innerText     = 'Call Next';
            callNextBtn.disabled      = false;
            callNextBtn.style.opacity = '1';
        }
    });

    // ── Skip ──────────────────────────────────────────────────────────────────
    const skipBtn = document.getElementById('skipBtn');
    if (skipBtn) {
        skipBtn.addEventListener('click', async () => {
            if (skipBtn.disabled) return;
            if (!currentServingNumber) { showToast('No current ticket to skip', 'info'); return; }

            // Stop countdown if it's running
            if (countdownInterval) {
                clearInterval(countdownInterval);
                countdownInterval = null;
            }

            skipBtn.disabled          = true;
            skipBtn.style.opacity     = '0.6';
            callNextBtn.disabled      = true;
            callNextBtn.style.opacity = '0.6';

            try {
                const response = await fetch(`${API_BASE}/skip/${currentServingNumber}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ officeId })
                });

                if (!response.ok) {
                    if (response.status === 404) {
                        const nextRes = await fetch(`${API_BASE}/next`, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ officeId })
                        });
                        if (!nextRes.ok) throw new Error(`HTTP ${nextRes.status}`);
                    } else {
                        throw new Error(`HTTP ${response.status}`);
                    }
                }

                console.log(`Skipped ticket #${formatTicketNumber(currentServingNumber)}`);
                skipBtn.innerText = '✓ Skipped';

                setTimeout(() => {
                    skipBtn.style.display     = 'none';
                    skipBtn.innerText         = 'Skip Ticket';
                    callNextBtn.innerText     = 'Call Next';
                    callNextBtn.disabled      = false;
                    callNextBtn.style.opacity = '1';
                }, 3000);

                await refresh();
            } catch (error) {
                console.error('Error skipping ticket:', error);
                showToast('Failed to skip ticket', 'error');
                skipBtn.disabled          = false;
                skipBtn.style.opacity     = '1';
                callNextBtn.disabled      = false;
                callNextBtn.style.opacity = '1';
            }
        });
    }

    // ── Total Time button ─────────────────────────────────────────────────────
    const totalTimeBtn = document.getElementById('totalTimeBtn');
    if (totalTimeBtn) {
        totalTimeBtn.addEventListener('click', () => {
            const grandTotal = completedSecondsTotal + liveElapsed();
            showToast(`Total Time Served Today: ${formatMMSS(grandTotal)}`, 'info');
        });
    }

    // ── Boot ──────────────────────────────────────────────────────────────────
    refresh();
    setInterval(refresh, 2000);
});

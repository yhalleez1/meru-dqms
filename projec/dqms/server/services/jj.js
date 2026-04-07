function announceTicket(ticketNumber) {
    const text = `Attention please. Number ${formattedTicket}, kindly proceed to ${officeName}`;
    const speech = new SpeechSynthesisUtterance(text);
    window.speechSynthesis.speak(speech);
}
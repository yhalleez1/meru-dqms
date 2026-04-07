from playsound import playsound
import pyttsx3
import time

engine = pyttsx3.init()
engine.setProperty('rate', 110)

playsound("beep.mp3")  # 🔊 beep
time.sleep(0.3)

engine.say("Attention please. Number 008, proceed to counter 3")
engine.runAndWait()

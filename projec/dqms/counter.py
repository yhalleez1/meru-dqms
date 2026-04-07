import pyttsx3

engine = pyttsx3.init()

# 🔧 Adjust voice properties
engine.setProperty('rate', 120)   # slower (default ~200)
engine.setProperty('volume', 1.0) # max volume

# The staff inputs the number and counter
number = "008"
counter = "3"

# Create the sentence
text = f"Please, let number {number}, proceed to counter {counter}"

# Speak it
engine.say(text)
engine.runAndWait()
